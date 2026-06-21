import Foundation
import Combine

class DiskSpeedTestViewModel: ObservableObject {
    @Published var fileSize: Double = 10 { // Default 10 MB
        didSet { UserDefaults.standard.set(fileSize, forKey: "fileSize") }
    }
    @Published var iterations: Int = 100 { // Default 100 iterations
        didSet { UserDefaults.standard.set(iterations, forKey: "iterations") }
    }
    @Published var isRunning = false
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

    private let fileManager = FileManager.default
    private var securityScopedResource: URL? = nil

    init() {
        // Load persisted settings (didSet will re-save on the assignments, which is harmless)
        let savedSize = UserDefaults.standard.double(forKey: "fileSize")
        if savedSize >= 0.1 { fileSize = savedSize }
        let savedIters = UserDefaults.standard.integer(forKey: "iterations")
        if savedIters >= 1 { iterations = savedIters }

        loadTestDirectoryBookmark()
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
        
        addLog("Starting tests with file size: \(String(format: "%.2f", fileSize)) MB and \(iterations) iterations")
        
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
            
            DispatchQueue.main.async {
                self.isRunning = false
                self.addLog("All tests completed")
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
    }

    private func resetResults() {
        results = results.map { TestResult(name: $0.name) }
    }

    private func updateTest(index: Int, name: String, operation: () -> Double) {
        let speed = operation()
        DispatchQueue.main.async {
            self.results[index].speeds.append(speed)
            self.results[index].sortedSpeeds = self.results[index].speeds.enumerated().sorted { $0.element < $1.element }
            
            self.addLog("\(name) - Speed: \(String(format: "%.2f", speed)) MB/s, Min: \(String(format: "%.2f", self.results[index].minSpeed)) MB/s, Avg: \(String(format: "%.2f", self.results[index].avgSpeed)) MB/s, Max: \(String(format: "%.2f", self.results[index].maxSpeed)) MB/s")
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
        Location:   \(location)

        """
        func row(_ name: String, _ a: String, _ b: String, _ c: String) -> String {
            var line = pad(name, 18)
            line += pad(a, 11)
            line += pad(b, 11)
            line += pad(c, 11)
            return line
        }
        out += row("Test", "Min", "Avg", "Max") + "(MB/s)\n"
        for r in results where !r.speeds.isEmpty {
            let minS = String(format: "%.2f", r.minSpeed)
            let avgS = String(format: "%.2f", r.avgSpeed)
            let maxS = String(format: "%.2f", r.maxSpeed)
            out += row(r.name, minS, avgS, maxS) + "\n"
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
    
    // Disk operation methods
    private func sequentialWrite(size: Int, to url: URL) -> Double {
        let data = Data(count: size)
        let start = Date()
        
        do {
            try data.write(to: url)
        } catch {
            addLog("Error in sequential write: \(error)")
            return 0
        }
        
        let end = Date()
        let timeInterval = end.timeIntervalSince(start)
        return Double(size) / timeInterval / (1024 * 1024) // MB/s
    }
    
    private func sequentialRead(from url: URL) -> Double {
        let start = Date()
        
        do {
            _ = try Data(contentsOf: url)
        } catch {
            addLog("Error in sequential read: \(error)")
            return 0
        }
        
        let end = Date()
        let timeInterval = end.timeIntervalSince(start)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Double(fileSize) / timeInterval / (1024 * 1024) // MB/s
    }
    
    private func randomWrite(size: Int, to url: URL) -> Double {
        let chunkSize = 4096 // 4 KB chunks
        let chunks = size / chunkSize
        let data = Data(count: chunkSize)
        let start = Date()
        
        do {
            let fileHandle = try FileHandle(forWritingTo: url)
            defer { fileHandle.closeFile() }
            
            for _ in 0..<chunks {
                guard isRunning else { break }
                let offset = UInt64(arc4random_uniform(UInt32(size)))
                fileHandle.seek(toFileOffset: offset)
                fileHandle.write(data)
            }
        } catch {
            addLog("Error in random write: \(error)")
            return 0
        }
        
        let end = Date()
        let timeInterval = end.timeIntervalSince(start)
        return Double(size) / timeInterval / (1024 * 1024) // MB/s
    }
    
    private func randomRead(from url: URL) -> Double {
        let chunkSize = 4096 // 4 KB chunks
        let start = Date()
        
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { fileHandle.closeFile() }
            
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let chunks = fileSize / chunkSize
            
            for _ in 0..<chunks {
                guard isRunning else { break }
                let offset = UInt64(arc4random_uniform(UInt32(fileSize)))
                fileHandle.seek(toFileOffset: offset)
                _ = fileHandle.readData(ofLength: chunkSize)
            }
        } catch {
            addLog("Error in random read: \(error)")
            return 0
        }
        
        let end = Date()
        let timeInterval = end.timeIntervalSince(start)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Double(fileSize) / timeInterval / (1024 * 1024) // MB/s
    }
}

struct TestResult: Identifiable {
    let id = UUID()
    let name: String
    var speeds: [Double] = []
    var sortedSpeeds: [(offset: Int, element: Double)] = []
    
    var minSpeed: Double { speeds.min() ?? 0 }
    var avgSpeed: Double { speeds.isEmpty ? 0 : speeds.reduce(0, +) / Double(speeds.count) }
    var maxSpeed: Double { speeds.max() ?? 0 }
}
