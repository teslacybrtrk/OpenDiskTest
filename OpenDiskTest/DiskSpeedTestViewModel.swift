import Foundation
import Combine
import DiskArbitration
import IOKit

class DiskSpeedTestViewModel: ObservableObject {
    @Published var fileSize: Double = 10 { // Default 10 MB
        didSet { UserDefaults.standard.set(fileSize, forKey: "fileSize") }
    }
    @Published var iterations: Int = 100 { // Default 100 iterations
        didSet { UserDefaults.standard.set(iterations, forKey: "iterations") }
    }
    /// I/O block size in KB used for random tests (and the sequential streaming chunk).
    /// Larger blocks favor throughput; smaller blocks stress IOPS.
    @Published var blockSizeKB: Int = 4 {
        didSet { UserDefaults.standard.set(blockSizeKB, forKey: "blockSizeKB") }
    }
    /// When true, disables the OS file cache (F_NOCACHE) so results reflect true disk
    /// speed instead of RAM. On by default for trustworthy numbers.
    @Published var bypassCache: Bool = true {
        didSet { UserDefaults.standard.set(bypassCache, forKey: "bypassCache") }
    }
    @Published var isRunning = false

    /// Supported block sizes for the picker (KB).
    static let blockSizeOptions = [4, 64, 1024]
    private var blockSizeBytes: Int { max(1, blockSizeKB) * 1024 }
    @Published var currentIteration: Int = 0

    var progress: Double {
        iterations > 0 ? Double(currentIteration) / Double(iterations) : 0
    }

    var canStartTests: Bool {
        !isRunning && fileSize >= 0.1 && fileSize <= 4096 && iterations >= 1 && iterations <= 1000
    }

    @Published var results: [TestResult] = [
        TestResult(name: "Sequential Write"),
        TestResult(name: "Sequential Read"),
        TestResult(name: "Random Write"),
        TestResult(name: "Random Read")
    ]
    @Published var logs: [String] = []

    /// nil = use system temporary directory. When set, tests run in the user-chosen folder (persisted via security-scoped bookmark).
    @Published var testDirectory: URL? = nil

    /// Info about the volume the tests will run on (model, SSD/HDD, connection, capacity).
    @Published var driveInfo: DriveInfo? = nil

    /// Saved results of past completed runs (most recent first), persisted as JSON.
    @Published var history: [BenchmarkRun] = []
    private let historyKey = "benchmarkHistory"
    private let historyLimit = 50

    private let fileManager = FileManager.default
    private var securityScopedResource: URL? = nil

    init() {
        // Load persisted settings (didSet will re-save on the assignments, which is harmless)
        let savedSize = UserDefaults.standard.double(forKey: "fileSize")
        if savedSize >= 0.1 { fileSize = savedSize }
        let savedIters = UserDefaults.standard.integer(forKey: "iterations")
        if savedIters >= 1 { iterations = savedIters }
        let savedBlock = UserDefaults.standard.integer(forKey: "blockSizeKB")
        if Self.blockSizeOptions.contains(savedBlock) { blockSizeKB = savedBlock }
        if UserDefaults.standard.object(forKey: "bypassCache") != nil {
            bypassCache = UserDefaults.standard.bool(forKey: "bypassCache")
        }

        loadTestDirectoryBookmark()
        refreshDriveInfo()
        loadHistory()
    }

    // MARK: - Presets

    func applyPreset(_ preset: BenchmarkPreset) {
        fileSize = preset.fileSizeMB
        iterations = preset.iterations
        blockSizeKB = preset.blockSizeKB
        addLog("Applied preset: \(preset.name)")
    }

    // MARK: - Benchmark history

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let runs = try? JSONDecoder().decode([BenchmarkRun].self, from: data) else { return }
        history = runs
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    func clearHistory() {
        history.removeAll()
        UserDefaults.standard.removeObject(forKey: historyKey)
        addLog("Benchmark history cleared")
    }

    /// Snapshots the just-completed run into history.
    private func recordRun() {
        guard hasResults else { return }
        let entries = results.filter { !$0.speeds.isEmpty }.map {
            BenchmarkRun.Entry(name: $0.name, avgMBps: $0.avgSpeed, avgIOPS: $0.isRandom ? $0.avgIOPS : nil)
        }
        let run = BenchmarkRun(
            id: UUID(),
            date: Date(),
            build: String(BuildInfo.commitSHA.prefix(7)),
            volumeName: driveInfo?.volumeName,
            mediaKind: driveInfo?.mediaKind,
            locationPath: testDirectory?.path ?? "System temp directory",
            fileSizeMB: fileSize,
            iterations: iterations,
            blockSizeKB: blockSizeKB,
            bypassCache: bypassCache,
            entries: entries
        )
        history.insert(run, at: 0)
        if history.count > historyLimit { history = Array(history.prefix(historyLimit)) }
        saveHistory()
        addLog("Saved run to history (\(history.count) total)")
    }

    /// Loads volume/device details for the active test location off the main thread.
    func refreshDriveInfo() {
        let url = testDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let info = DriveInfo.load(for: url)
            DispatchQueue.main.async { self?.driveInfo = info }
        }
    }

    private func loadTestDirectoryBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "testDirectoryBookmark") else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                UserDefaults.standard.removeObject(forKey: "testDirectoryBookmark")
                return
            }
            testDirectory = url
            if url.startAccessingSecurityScopedResource() {
                securityScopedResource = url
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: "testDirectoryBookmark")
        }
    }

    func runTests() {
        guard canStartTests else {
            addLog("Invalid parameters: file size must be 0.1–4096 MB and iterations 1–1000")
            return
        }

        isRunning = true
        currentIteration = 0
        results = results.map { TestResult(name: $0.name) }
        logs.removeAll()
        
        addLog("Starting tests — file size: \(String(format: "%.2f", fileSize)) MB, \(iterations) iterations, block \(blockSizeKB) KB, cache \(bypassCache ? "bypassed (F_NOCACHE)" : "enabled")")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let testFileURL = self.getTestFileURL()
            let fileSizeBytes = Int(self.fileSize * 1024 * 1024)
            
            self.addLog("Test file location: \(testFileURL.path)")
            
            // Ensure the file exists before testing
            if !self.fileManager.fileExists(atPath: testFileURL.path) {
                do {
                    try "".write(to: testFileURL, atomically: true, encoding: .utf8)
                    self.addLog("Created test file at: \(testFileURL.path)")
                } catch {
                    self.addLog("Error creating test file: \(error)")
                    DispatchQueue.main.async {
                        self.isRunning = false
                    }
                    return
                }
            }
            
            for iteration in 1...self.iterations {
                guard self.isRunning else { break }

                DispatchQueue.main.async { self.currentIteration = iteration }

                self.addLog("Starting iteration \(iteration)")
                
                self.updateTest(index: 0, name: "Sequential Write") { self.sequentialWrite(size: fileSizeBytes, to: testFileURL) }
                self.updateTest(index: 1, name: "Sequential Read") { self.sequentialRead(from: testFileURL) }
                self.updateTest(index: 2, name: "Random Write") { self.randomWrite(size: fileSizeBytes, to: testFileURL) }
                self.updateTest(index: 3, name: "Random Read") { self.randomRead(from: testFileURL) }
                
                self.addLog("Completed iteration \(iteration)")
            }
            
            let completedNaturally = self.isRunning // false if the user pressed Stop
            DispatchQueue.main.async {
                self.isRunning = false
                self.addLog("All tests completed")
                if completedNaturally { self.recordRun() }
            }

            try? self.fileManager.removeItem(at: testFileURL)
            self.addLog("Removed test file from: \(testFileURL.path)")
        }
    }
    
    func stopTests() {
        isRunning = false
        addLog("Tests stopped by user")
    }

    // MARK: - Test location (custom directory support)

    func chooseTestDirectory(_ url: URL) {
        // Release previous scoped access
        if let prev = securityScopedResource {
            prev.stopAccessingSecurityScopedResource()
            securityScopedResource = nil
        }

        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "testDirectoryBookmark")

            var isStale = false
            let resolved = try URL(resolvingBookmarkData: bookmark,
                                   options: .withSecurityScope,
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &isStale)
            if isStale {
                addLog("Selected directory bookmark is stale; falling back to temporary directory")
                resetToTemporaryDirectory()
                return
            }

            testDirectory = resolved
            if resolved.startAccessingSecurityScopedResource() {
                securityScopedResource = resolved
            }
            addLog("Test location set to: \(resolved.path)")
            resetResults()
            refreshDriveInfo()
        } catch {
            addLog("Failed to bookmark chosen test directory: \(error)")
        }
    }

    func resetToTemporaryDirectory() {
        if let prev = securityScopedResource {
            prev.stopAccessingSecurityScopedResource()
            securityScopedResource = nil
        }
        UserDefaults.standard.removeObject(forKey: "testDirectoryBookmark")
        testDirectory = nil
        addLog("Test location reset to temporary directory")
        resetResults()
        refreshDriveInfo()
    }

    private func resetResults() {
        results = results.map { TestResult(name: $0.name) }
    }

    private func updateTest(index: Int, name: String, operation: () -> Measurement) {
        let m = operation()
        DispatchQueue.main.async {
            self.results[index].speeds.append(m.mbps)
            if let iops = m.iops { self.results[index].iopsSamples.append(iops) }
            self.results[index].sortedSpeeds = self.results[index].speeds.enumerated().sorted { $0.element < $1.element }

            let iopsNote = m.iops.map { String(format: ", %.0f IOPS", $0) } ?? ""
            self.addLog("\(name) - \(String(format: "%.2f", m.mbps)) MB/s\(iopsNote) (avg \(String(format: "%.2f", self.results[index].avgSpeed)) MB/s)")
        }
    }
    
    /// True once at least one test has recorded a measurement.
    var hasResults: Bool { results.contains { !$0.speeds.isEmpty } }

    /// Builds a plain-text, shareable report of the current run (config + per-test
    /// min/avg/max). Used by the "Copy Results" button.
    func resultsReport() -> String {
        func pad(_ s: String, _ width: Int) -> String {
            s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
        }
        let location = testDirectory?.path ?? "System temp directory"
        var out = """
        OpenDiskTest Results
        Build:      \(String(BuildInfo.commitSHA.prefix(7)))
        Date:       \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))
        File size:  \(String(format: "%.2f", fileSize)) MB
        Iterations: \(iterations)
        Block size: \(blockSizeKB) KB
        Cache:      \(bypassCache ? "bypassed (F_NOCACHE)" : "enabled")
        Location:   \(location)

        """
        func row(_ name: String, _ a: String, _ b: String, _ c: String, _ d: String) -> String {
            var line = pad(name, 18)
            line += pad(a, 11)
            line += pad(b, 11)
            line += pad(c, 11)
            line += d
            return line
        }
        out += row("Test", "Min", "Avg", "Max", "(MB/s) | IOPS") + "\n"
        for r in results where !r.speeds.isEmpty {
            let minS = String(format: "%.2f", r.minSpeed)
            let avgS = String(format: "%.2f", r.avgSpeed)
            let maxS = String(format: "%.2f", r.maxSpeed)
            let iopsS = r.isRandom ? String(format: "%.0f IOPS", r.avgIOPS) : ""
            out += row(r.name, minS, avgS, maxS, iopsS) + "\n"
        }
        return out
    }

    func addLog(_ message: String) {
        DispatchQueue.main.async {
            self.logs.append("[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(message)")
        }
    }
    
    private func getTestFileURL() -> URL {
        let baseDir = testDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDir.appendingPathComponent("diskspeedtest.tmp")
    }
    
    // MARK: - Disk operations

    /// Disables the OS file cache on a handle when bypassCache is on, so measurements
    /// reflect the device rather than RAM.
    private func applyCachePolicy(_ handle: FileHandle) {
        if bypassCache {
            _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)
        }
    }

    private func megabytesPerSecond(bytes: Int, seconds: Double) -> Double {
        seconds > 0 ? Double(bytes) / seconds / (1024 * 1024) : 0
    }

    private func sequentialWrite(size: Int, to url: URL) -> Measurement {
        let block = blockSizeBytes
        let chunk = Data(count: block)
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            applyCachePolicy(handle)
            handle.truncateFile(atOffset: 0)

            let start = Date()
            var written = 0
            while written < size {
                guard isRunning else { break }
                let remaining = size - written
                handle.write(remaining >= block ? chunk : chunk.prefix(remaining))
                written += min(block, remaining)
            }
            fsync(handle.fileDescriptor) // ensure data actually reaches the device
            let seconds = Date().timeIntervalSince(start)
            return Measurement(mbps: megabytesPerSecond(bytes: written, seconds: seconds), iops: nil)
        } catch {
            addLog("Error in sequential write: \(error)")
            return Measurement(mbps: 0, iops: nil)
        }
    }

    private func sequentialRead(from url: URL) -> Measurement {
        let block = blockSizeBytes
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            applyCachePolicy(handle)

            let start = Date()
            var total = 0
            while isRunning {
                let data = handle.readData(ofLength: block)
                if data.isEmpty { break }
                total += data.count
            }
            let seconds = Date().timeIntervalSince(start)
            return Measurement(mbps: megabytesPerSecond(bytes: total, seconds: seconds), iops: nil)
        } catch {
            addLog("Error in sequential read: \(error)")
            return Measurement(mbps: 0, iops: nil)
        }
    }

    private func randomWrite(size: Int, to url: URL) -> Measurement {
        let block = blockSizeBytes
        let blockCount = max(1, size / block)
        let data = Data(count: block)
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            applyCachePolicy(handle)

            var ops = 0
            let start = Date()
            for _ in 0..<blockCount {
                guard isRunning else { break }
                // Block-aligned random offset (required for good F_NOCACHE behavior).
                let offset = UInt64(Int.random(in: 0..<blockCount) * block)
                handle.seek(toFileOffset: offset)
                handle.write(data)
                ops += 1
            }
            fsync(handle.fileDescriptor)
            let seconds = Date().timeIntervalSince(start)
            return Measurement(mbps: megabytesPerSecond(bytes: ops * block, seconds: seconds),
                               iops: seconds > 0 ? Double(ops) / seconds : 0)
        } catch {
            addLog("Error in random write: \(error)")
            return Measurement(mbps: 0, iops: 0)
        }
    }

    private func randomRead(from url: URL) -> Measurement {
        let block = blockSizeBytes
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let blockCount = max(1, fileSize / block)
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            applyCachePolicy(handle)

            var ops = 0
            let start = Date()
            for _ in 0..<blockCount {
                guard isRunning else { break }
                let offset = UInt64(Int.random(in: 0..<blockCount) * block)
                handle.seek(toFileOffset: offset)
                _ = handle.readData(ofLength: block)
                ops += 1
            }
            let seconds = Date().timeIntervalSince(start)
            return Measurement(mbps: megabytesPerSecond(bytes: ops * block, seconds: seconds),
                               iops: seconds > 0 ? Double(ops) / seconds : 0)
        } catch {
            addLog("Error in random read: \(error)")
            return Measurement(mbps: 0, iops: 0)
        }
    }
}

/// One timed sample: throughput in MB/s, plus IOPS for the random tests.
struct Measurement {
    let mbps: Double
    let iops: Double?
}

/// Details about the volume/device the tests run on.
struct DriveInfo {
    var volumeName: String
    var totalBytes: Int64
    var freeBytes: Int64
    var fileSystem: String
    var connection: String?     // "USB", "Thunderbolt", "PCI-Express", "SATA"…
    var mediaName: String?      // device model
    var isSolidState: Bool?

    var usedBytes: Int64 { max(0, totalBytes - freeBytes) }
    var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
    /// "SSD" / "HDD" / nil when unknown.
    var mediaKind: String? {
        guard let ssd = isSolidState else { return nil }
        return ssd ? "SSD" : "HDD"
    }

    static func load(for url: URL) -> DriveInfo {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let values = try? url.resourceValues(forKeys: keys)
        let name = values?.volumeName ?? "Unknown Volume"
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let free = Int64(values?.volumeAvailableCapacity ?? 0)

        // Filesystem type + BSD device name via statfs.
        var fsType = "—"
        var bsdName: String?
        var fs = statfs()
        if statfs((url as NSURL).fileSystemRepresentation, &fs) == 0 {
            fsType = withUnsafeBytes(of: &fs.f_fstypename) { raw in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            let mnt = withUnsafeBytes(of: &fs.f_mntfromname) { raw in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            if mnt.hasPrefix("/dev/") { bsdName = String(mnt.dropFirst("/dev/".count)) }
        }

        var connection: String?
        var media: String?
        if let bsd = bsdName,
           let session = DASessionCreate(kCFAllocatorDefault),
           let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsd),
           let desc = DADiskCopyDescription(disk) as? [String: Any] {
            connection = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String
            media = (desc[kDADiskDescriptionDeviceModelKey as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return DriveInfo(
            volumeName: name,
            totalBytes: total,
            freeBytes: free,
            fileSystem: prettyFileSystem(fsType),
            connection: connection?.trimmingCharacters(in: .whitespacesAndNewlines),
            mediaName: (media?.isEmpty == false) ? media : nil,
            isSolidState: bsdName.flatMap { isSolidState(bsdName: $0) }
        )
    }

    private static func prettyFileSystem(_ raw: String) -> String {
        switch raw.lowercased() {
        case "apfs": return "APFS"
        case "hfs": return "HFS+"
        case "msdos", "exfat": return raw.uppercased()
        case "ntfs": return "NTFS"
        case "": return "—"
        default: return raw.uppercased()
        }
    }

    /// Reduce a slice name ("disk3s1") to its whole disk ("disk3").
    private static func wholeDisk(of bsd: String) -> String {
        if let range = bsd.range(of: "^disk[0-9]+", options: .regularExpression) {
            return String(bsd[range])
        }
        return bsd
    }

    /// Reads the IOKit "Medium Type" for the device to classify SSD vs HDD.
    private static func isSolidState(bsdName: String) -> Bool? {
        let whole = wholeDisk(of: bsdName)
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, whole) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        let prop = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            "Device Characteristics" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        )
        if let dict = prop as? [String: Any], let medium = dict["Medium Type"] as? String {
            return medium.lowercased().contains("solid")
        }
        return nil
    }
}

/// A one-click benchmark configuration.
struct BenchmarkPreset: Identifiable {
    let name: String
    let fileSizeMB: Double
    let iterations: Int
    let blockSizeKB: Int
    var id: String { name }

    static let all: [BenchmarkPreset] = [
        BenchmarkPreset(name: "Quick",    fileSizeMB: 64,  iterations: 3, blockSizeKB: 1024),
        BenchmarkPreset(name: "Default",  fileSizeMB: 128, iterations: 5, blockSizeKB: 1024),
        BenchmarkPreset(name: "Thorough", fileSizeMB: 512, iterations: 9, blockSizeKB: 1024),
        BenchmarkPreset(name: "4K IOPS",  fileSizeMB: 128, iterations: 5, blockSizeKB: 4),
    ]
}

/// A persisted snapshot of one completed run, used by the History view.
struct BenchmarkRun: Codable, Identifiable {
    let id: UUID
    let date: Date
    let build: String
    let volumeName: String?
    let mediaKind: String?
    let locationPath: String
    let fileSizeMB: Double
    let iterations: Int
    let blockSizeKB: Int
    let bypassCache: Bool
    let entries: [Entry]

    struct Entry: Codable {
        let name: String
        let avgMBps: Double
        let avgIOPS: Double?
    }

    var configSummary: String {
        "\(String(format: "%.0f", fileSizeMB)) MB · \(iterations)× · \(blockSizeKB) KB · cache \(bypassCache ? "off" : "on")"
    }
}

struct TestResult: Identifiable {
    let id = UUID()
    let name: String
    var speeds: [Double] = []
    var iopsSamples: [Double] = []
    var sortedSpeeds: [(offset: Int, element: Double)] = []

    var isRandom: Bool { name.localizedCaseInsensitiveContains("Random") }
    var minSpeed: Double { speeds.min() ?? 0 }
    var avgSpeed: Double { speeds.isEmpty ? 0 : speeds.reduce(0, +) / Double(speeds.count) }
    var maxSpeed: Double { speeds.max() ?? 0 }
    var avgIOPS: Double { iopsSamples.isEmpty ? 0 : iopsSamples.reduce(0, +) / Double(iopsSamples.count) }
}
