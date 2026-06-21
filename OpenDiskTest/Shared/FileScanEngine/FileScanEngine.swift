import Foundation

// MARK: - CancelToken
//
// A tiny thread-safe flag for cancelling a background scan from the main actor.

final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

// MARK: - FileScanEngine
//
// One reusable recursive filesystem walker shared by the Space Analyzer,
// Duplicate Finder, and Cleanup tools. Builds a ScanNode tree of allocated
// sizes, tolerates permission errors (collecting skipped URLs rather than
// failing), skips symlinks to avoid cycles/double-counting, and treats bundles
// as sized leaves to bound tree size. Progress is reported throttled; the caller
// supplies a cancellation check.

final class FileScanEngine {
    private let fm = FileManager.default
    private let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isRegularFileKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey
    ]

    private var filesScanned = 0
    private var bytesScanned: Int64 = 0
    private var skipped: [URL] = []
    private var lastReport = Date.distantPast
    private var isCancelled: () -> Bool = { false }
    private var onProgress: (ScanProgress) -> Void = { _ in }

    /// Scans `root` and returns the built tree. `includeHidden` controls whether
    /// dotfiles are counted (default true — hidden files consume space too).
    func scan(root: URL,
              includeHidden: Bool = true,
              isCancelled: @escaping () -> Bool = { false },
              onProgress: @escaping (ScanProgress) -> Void = { _ in }) -> ScanResult {
        self.filesScanned = 0
        self.bytesScanned = 0
        self.skipped = []
        self.isCancelled = isCancelled
        self.onProgress = onProgress

        let rootNode = walk(url: root, includeHidden: includeHidden)
        let cancelled = isCancelled()
        report(force: true, path: cancelled ? "Cancelled" : "Done")
        return ScanResult(root: rootNode,
                          filesScanned: filesScanned,
                          totalBytes: rootNode.size,
                          skipped: skipped,
                          cancelled: cancelled)
    }

    private func walk(url: URL, includeHidden: Bool) -> ScanNode {
        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let node = ScanNode(url: url, name: name, isDirectory: true)

        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden { options.insert(.skipsHiddenFiles) }

        guard let entries = try? fm.contentsOfDirectory(at: url,
                                                        includingPropertiesForKeys: Array(resourceKeys),
                                                        options: options) else {
            skipped.append(url)
            return node
        }

        for entry in entries {
            if isCancelled() { break }
            guard let values = try? entry.resourceValues(forKeys: resourceKeys) else {
                skipped.append(entry)
                continue
            }
            // Never follow symlinks (cycles + double counting).
            if values.isSymbolicLink == true { continue }

            let isDir = values.isDirectory == true
            let isBundle = values.isPackage == true

            if isDir && !isBundle {
                let child = walk(url: entry, includeHidden: includeHidden)
                child.parent = node
                node.children.append(child)
                node.size += child.size
                node.fileCount += child.fileCount
            } else if isDir && isBundle {
                // Bundle: sized leaf, don't expand its internals into the tree.
                let (size, count) = bundleSize(entry)
                let leaf = ScanNode(url: entry, name: entry.lastPathComponent, isDirectory: true,
                                    isBundle: true, size: size, fileCount: count)
                leaf.parent = node
                node.children.append(leaf)
                node.size += size
                node.fileCount += count
                filesScanned += count
                bytesScanned += size
            } else {
                let size = allocatedSize(values)
                let leaf = ScanNode(url: entry, name: entry.lastPathComponent, isDirectory: false,
                                    size: size, fileCount: 1)
                leaf.parent = node
                node.children.append(leaf)
                node.size += size
                node.fileCount += 1
                filesScanned += 1
                bytesScanned += size
            }
            report(force: false, path: entry.path)
        }
        return node
    }

    /// Fast recursive size of a bundle without retaining child nodes.
    private func bundleSize(_ url: URL) -> (Int64, Int) {
        var total: Int64 = 0
        var count = 0
        guard let en = fm.enumerator(at: url,
                                     includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey],
                                     options: [], errorHandler: { [weak self] failURL, _ in
                                         self?.skipped.append(failURL); return true
                                     }) else {
            return (0, 0)
        }
        for case let item as URL in en {
            if isCancelled() { break }
            guard let values = try? item.resourceValues(forKeys: resourceKeys) else { continue }
            if values.isRegularFile == true {
                total += allocatedSize(values)
                count += 1
            }
        }
        return (total, count)
    }

    private func allocatedSize(_ values: URLResourceValues) -> Int64 {
        if let a = values.totalFileAllocatedSize { return Int64(a) }
        if let a = values.fileAllocatedSize { return Int64(a) }
        if let s = values.fileSize { return Int64(s) }
        return 0
    }

    private func report(force: Bool, path: String) {
        let now = Date()
        if !force && now.timeIntervalSince(lastReport) < 0.1 { return }
        lastReport = now
        let progress = ScanProgress(filesScanned: filesScanned,
                                    bytesScanned: bytesScanned,
                                    currentPath: path,
                                    skippedCount: skipped.count)
        onProgress(progress)
    }
}
