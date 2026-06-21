import SwiftUI

// MARK: - CleanupViewModel
//
// Finds reclaimable space in well-known locations and cleans the selected ones.
// Safety model: nothing is pre-selected; every category moves its contents to
// the Trash (recoverable) EXCEPT emptying the Trash itself, which is permanent
// and clearly flagged. Each category carries a plain-language safety note.

struct CleanupCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let blurb: String
    let url: URL              // container whose *contents* are cleaned
    let permanent: Bool       // true only for the Trash category
    let caution: String?      // extra warning shown in the row
}

@MainActor
final class CleanupViewModel: ObservableObject {
    @Published var categories: [CleanupCategory] = []
    @Published var sizes: [String: Int64] = [:]      // category id → bytes
    @Published var scanning = false
    @Published var scannedCount = 0
    @Published var selection: Set<String> = []        // nothing pre-selected
    @Published var lastCleaned: Int64?

    private var cancelToken = CancelToken()

    init() {
        categories = Self.buildCategories()
    }

    var totalReclaimable: Int64 { sizes.values.reduce(0, +) }
    var selectedBytes: Int64 { selection.reduce(0) { $0 + (sizes[$1] ?? 0) } }

    func scan() {
        guard !scanning else { return }
        scanning = true
        scannedCount = 0
        sizes = [:]
        lastCleaned = nil
        let token = CancelToken(); cancelToken = token
        let cats = categories

        Task.detached(priority: .userInitiated) { [weak self] in
            for cat in cats {
                if token.isCancelled { break }
                let size = Self.directorySize(cat.url, token: token)
                await MainActor.run { [weak self] in
                    self?.sizes[cat.id] = size
                    self?.scannedCount += 1
                }
            }
            await MainActor.run { [weak self] in self?.scanning = false }
        }
    }

    func cancel() { cancelToken.cancel(); scanning = false }

    func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func clean() {
        let fm = FileManager.default
        var freed: Int64 = 0
        for cat in categories where selection.contains(cat.id) {
            guard let contents = try? fm.contentsOfDirectory(at: cat.url,
                                                             includingPropertiesForKeys: nil,
                                                             options: []) else { continue }
            for item in contents {
                do {
                    if cat.permanent {
                        try fm.removeItem(at: item)
                    } else {
                        try fm.trashItem(at: item, resultingItemURL: nil)
                    }
                } catch {
                    continue   // skip locked / in-use items
                }
            }
            freed += sizes[cat.id] ?? 0
            sizes[cat.id] = 0
        }
        lastCleaned = freed
        selection.removeAll()
    }

    // MARK: Sizing

    nonisolated private static func directorySize(_ url: URL, token: CancelToken) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                     options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in en {
            if token.isCancelled { break }
            guard let v = try? item.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
        }
        return total
    }

    // MARK: Categories

    private static func buildCategories() -> [CleanupCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let lib = home.appendingPathComponent("Library")
        let xcode = lib.appendingPathComponent("Developer/Xcode")
        var cats: [CleanupCategory] = [
            CleanupCategory(id: "caches", name: "User Caches", icon: "shippingbox.fill",
                            blurb: "App caches that regenerate automatically when needed.",
                            url: lib.appendingPathComponent("Caches"),
                            permanent: false, caution: nil),
            CleanupCategory(id: "logs", name: "Logs", icon: "doc.text.fill",
                            blurb: "Diagnostic and crash logs from apps and the system.",
                            url: lib.appendingPathComponent("Logs"),
                            permanent: false, caution: nil),
            CleanupCategory(id: "derived", name: "Xcode DerivedData", icon: "hammer.fill",
                            blurb: "Build intermediates and indexes. Xcode rebuilds them on demand.",
                            url: xcode.appendingPathComponent("DerivedData"),
                            permanent: false, caution: nil),
            CleanupCategory(id: "devicesupport", name: "Xcode Device Support", icon: "iphone",
                            blurb: "Debug symbols cached for iOS versions you've connected.",
                            url: xcode.appendingPathComponent("iOS DeviceSupport"),
                            permanent: false, caution: nil),
            CleanupCategory(id: "archives", name: "Xcode Archives", icon: "archivebox.fill",
                            blurb: "Archived builds from past distributions.",
                            url: xcode.appendingPathComponent("Archives"),
                            permanent: false, caution: "Keep archives you may still need to notarize or re-export."),
            CleanupCategory(id: "trash", name: "Empty Trash", icon: "trash.fill",
                            blurb: "Permanently remove everything currently in the Trash.",
                            url: home.appendingPathComponent(".Trash"),
                            permanent: true, caution: "This is permanent — items cannot be restored.")
        ]
        // Only surface categories whose directory actually exists.
        cats = cats.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        return cats
    }
}
