import Foundation

// MARK: - ScanNode
//
// A node in the scanned filesystem tree. Reference type so directory totals can
// accumulate as children are added. Bundles (.app etc.) are stored as sized
// leaves rather than expanded, to bound tree size on large scans.

final class ScanNode: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let isBundle: Bool
    var size: Int64           // allocated bytes (accumulated for directories)
    var fileCount: Int        // files contained (1 for a leaf)
    var children: [ScanNode]
    weak var parent: ScanNode?

    init(url: URL, name: String, isDirectory: Bool, isBundle: Bool = false,
         size: Int64 = 0, fileCount: Int = 0, children: [ScanNode] = []) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isBundle = isBundle
        self.size = size
        self.fileCount = fileCount
        self.children = children
    }

    /// Children sorted largest-first (for treemap layout and lists).
    var sortedChildren: [ScanNode] {
        children.sorted { $0.size > $1.size }
    }

    func fractionOf(_ total: Int64) -> Double {
        total > 0 ? Double(size) / Double(total) : 0
    }
}

struct ScanProgress {
    var filesScanned: Int = 0
    var bytesScanned: Int64 = 0
    var currentPath: String = ""
    var skippedCount: Int = 0
}

struct ScanResult {
    let root: ScanNode
    let filesScanned: Int
    let totalBytes: Int64
    let skipped: [URL]
    let cancelled: Bool
}
