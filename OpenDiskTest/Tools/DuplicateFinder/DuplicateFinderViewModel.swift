import SwiftUI
import CryptoKit

// MARK: - DuplicateFinderViewModel
//
// Finds duplicate files (size bucket → partial hash → full SHA256) and the
// largest files under a chosen root. Hardlinked/same-inode entries are excluded
// from "reclaimable" totals since deleting one path frees nothing. Deletion
// always moves to Trash (recoverable), never unlink.

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let inodeKey: String         // "dev-ino" — identical for hardlinks
    let modified: Date?
    static func == (l: FileItem, r: FileItem) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let size: Int64
    let files: [FileItem]
    /// Bytes recoverable by trashing all but one real copy (hardlinks share storage).
    var wasted: Int64 {
        let distinctInodes = Set(files.map(\.inodeKey)).count
        return Int64(max(0, distinctInodes - 1)) * size
    }
}

@MainActor
final class DuplicateFinderViewModel: ObservableObject {
    enum Mode: String, CaseIterable { case duplicates = "Duplicates", largest = "Largest Files" }
    enum Stage: String { case idle, enumerating = "Scanning files…", hashing = "Comparing contents…", done }

    @Published var mode: Mode = .duplicates
    @Published var stage: Stage = .idle
    @Published var scanning = false
    @Published var filesSeen = 0
    @Published var bytesSeen: Int64 = 0
    @Published var hashProgress = 0.0

    @Published var groups: [DuplicateGroup] = []
    @Published var largest: [FileItem] = []
    @Published var totalWasted: Int64 = 0
    @Published var skippedCount = 0

    @Published var selection: Set<UUID> = []
    @Published var scanRootName = ""
    @Published var minSizeMB: Double = 1.0   // ignore files below this for noise control

    private var cancelToken = CancelToken()
    private let largestLimit = 200

    func scanHome() { scan(FileManager.default.homeDirectoryForCurrentUser) }

    func scan(_ url: URL) {
        guard !scanning else { return }
        scanning = true
        stage = .enumerating
        filesSeen = 0; bytesSeen = 0; hashProgress = 0
        groups = []; largest = []; totalWasted = 0; selection = []; skippedCount = 0
        scanRootName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent

        let token = CancelToken(); cancelToken = token
        let minBytes = Int64(minSizeMB * 1_000_000)

        Task.detached(priority: .userInitiated) { [weak self] in
            let (items, skipped) = Self.enumerateFiles(root: url, minBytes: minBytes, token: token) { seen, bytes in
                Task { @MainActor [weak self] in
                    self?.filesSeen = seen; self?.bytesSeen = bytes
                }
            }
            if token.isCancelled { await MainActor.run { [weak self] in self?.finishCancelled() }; return }

            await MainActor.run { [weak self] in
                self?.stage = .hashing
                self?.largest = Array(items.sorted { $0.size > $1.size }.prefix(self?.largestLimit ?? 200))
                self?.skippedCount = skipped
            }

            let dupGroups = Self.findDuplicates(items, token: token) { progress in
                Task { @MainActor [weak self] in self?.hashProgress = progress }
            }
            if token.isCancelled { await MainActor.run { [weak self] in self?.finishCancelled() }; return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.groups = dupGroups.sorted { $0.wasted > $1.wasted }
                self.totalWasted = self.groups.reduce(0) { $0 + $1.wasted }
                self.stage = .done
                self.scanning = false
            }
        }
    }

    func cancel() { cancelToken.cancel(); scanning = false; stage = .idle }

    private func finishCancelled() { scanning = false; stage = .idle }

    // MARK: Selection helpers

    func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// In every duplicate group, select all but the most recently modified file.
    func autoSelectDuplicates() {
        var sel = Set<UUID>()
        for group in groups {
            let sorted = group.files.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
            for file in sorted.dropFirst() { sel.insert(file.id) }
        }
        selection = sel
    }

    var selectedBytes: Int64 {
        let all = groups.flatMap(\.files) + largest
        return all.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    func trashSelected() {
        let all = groups.flatMap(\.files) + largest
        let toTrash = all.filter { selection.contains($0.id) }
        for file in toTrash {
            try? FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
        }
        // Drop trashed files from the model.
        let trashed = Set(toTrash.map(\.id))
        groups = groups.compactMap { g in
            let remaining = g.files.filter { !trashed.contains($0.id) }
            return remaining.count >= 2 ? DuplicateGroup(size: g.size, files: remaining) : nil
        }
        largest.removeAll { trashed.contains($0.id) }
        totalWasted = groups.reduce(0) { $0 + $1.wasted }
        selection.removeAll()
    }

    func revealInFinder(_ item: FileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: Enumeration

    nonisolated private static func enumerateFiles(root: URL, minBytes: Int64, token: CancelToken,
                                       onProgress: @escaping (Int, Int64) -> Void) -> ([FileItem], Int) {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
                                         .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]
        var items: [FileItem] = []
        var skipped = 0
        var seen = 0
        var bytes: Int64 = 0
        var lastReport = Date.distantPast

        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                     options: [], errorHandler: { _, _ in skipped += 1; return true }) else {
            return ([], 0)
        }
        for case let url as URL in en {
            if token.isCancelled { break }
            guard let v = try? url.resourceValues(forKeys: keys) else { skipped += 1; continue }
            if v.isPackage == true { en.skipDescendants(); continue }
            if v.isSymbolicLink == true { continue }
            guard v.isRegularFile == true else { continue }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
            seen += 1; bytes += size
            if size >= minBytes {
                items.append(FileItem(url: url, size: size,
                                      inodeKey: inodeKey(url.path),
                                      modified: v.contentModificationDate))
            }
            let now = Date()
            if now.timeIntervalSince(lastReport) > 0.1 { lastReport = now; onProgress(seen, bytes) }
        }
        onProgress(seen, bytes)
        return (items, skipped)
    }

    nonisolated private static func inodeKey(_ path: String) -> String {
        var s = stat()
        guard stat(path, &s) == 0 else { return UUID().uuidString }
        return "\(s.st_dev)-\(s.st_ino)"
    }

    // MARK: Duplicate detection pipeline

    nonisolated private static func findDuplicates(_ items: [FileItem], token: CancelToken,
                                       onProgress: @escaping (Double) -> Void) -> [DuplicateGroup] {
        // 1. Bucket by size; only sizes with ≥2 files are candidates.
        var bySize: [Int64: [FileItem]] = [:]
        for item in items { bySize[item.size, default: []].append(item) }
        let candidates = bySize.filter { $0.value.count >= 2 }

        let totalCandidates = candidates.reduce(0) { $0 + $1.value.count }
        var processed = 0
        var groups: [DuplicateGroup] = []

        for (size, sameSize) in candidates {
            if token.isCancelled { break }
            // 2. Partial hash (first + last 64KB).
            var byPartial: [String: [FileItem]] = [:]
            for file in sameSize {
                let key = partialHash(file.url) ?? "?"
                byPartial[key, default: []].append(file)
                processed += 1
            }
            onProgress(totalCandidates > 0 ? Double(processed) / Double(totalCandidates) : 1)

            // 3. Full hash within surviving partial-hash buckets.
            for (_, partialGroup) in byPartial where partialGroup.count >= 2 {
                if token.isCancelled { break }
                var byFull: [String: [FileItem]] = [:]
                for file in partialGroup {
                    let key = fullHash(file.url) ?? UUID().uuidString
                    byFull[key, default: []].append(file)
                }
                for (_, dupes) in byFull where dupes.count >= 2 {
                    groups.append(DuplicateGroup(size: size, files: dupes))
                }
            }
        }
        return groups
    }

    nonisolated private static func partialHash(_ url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        let head = (try? fh.read(upToCount: 65_536)) ?? Data()
        hasher.update(data: head)
        if let size = try? fh.seekToEnd(), size > 131_072 {
            try? fh.seek(toOffset: size - 65_536)
            let tail = (try? fh.read(upToCount: 65_536)) ?? Data()
            hasher.update(data: tail)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func fullHash(_ url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        while let chunk = try? fh.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
