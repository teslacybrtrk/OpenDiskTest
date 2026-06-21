import SwiftUI

// MARK: - SpaceAnalyzerViewModel
//
// Drives a background filesystem scan and the drill-down navigation over the
// resulting tree. Scanning runs off the main actor; progress and results are
// published back on main. Cancellation uses a thread-safe CancelToken.

@MainActor
final class SpaceAnalyzerViewModel: ObservableObject {
    @Published var scanning = false
    @Published var progress = ScanProgress()
    @Published var result: ScanResult?
    @Published var currentNode: ScanNode?
    @Published var breadcrumbs: [ScanNode] = []
    @Published var selected: ScanNode?
    @Published var includeHidden = true
    @Published var scanRootName = ""

    private var cancelToken = CancelToken()

    var canScanWholeDisk: Bool { true }

    func scanHome() {
        scan(FileManager.default.homeDirectoryForCurrentUser)
    }

    func scanWholeDisk() {
        scan(URL(fileURLWithPath: "/"))
    }

    func scan(_ url: URL) {
        guard !scanning else { return }
        scanning = true
        progress = ScanProgress()
        result = nil
        currentNode = nil
        breadcrumbs = []
        selected = nil
        scanRootName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent

        let token = CancelToken()
        cancelToken = token
        let hidden = includeHidden

        Task.detached(priority: .userInitiated) { [weak self] in
            let engine = FileScanEngine()
            let scanResult = engine.scan(
                root: url,
                includeHidden: hidden,
                isCancelled: { token.isCancelled },
                onProgress: { p in
                    Task { @MainActor [weak self] in self?.progress = p }
                })
            await MainActor.run { [weak self] in
                guard let self else { return }
                if !scanResult.cancelled {
                    self.result = scanResult
                    self.currentNode = scanResult.root
                    self.breadcrumbs = [scanResult.root]
                }
                self.scanning = false
            }
        }
    }

    func cancel() {
        cancelToken.cancel()
        scanning = false
    }

    // MARK: Drill-down

    func drillInto(_ node: ScanNode) {
        guard node.isDirectory, !node.isBundle, !node.children.isEmpty else {
            selected = node
            return
        }
        breadcrumbs.append(node)
        currentNode = node
        selected = nil
    }

    func goTo(breadcrumbIndex index: Int) {
        guard index < breadcrumbs.count else { return }
        breadcrumbs = Array(breadcrumbs.prefix(index + 1))
        currentNode = breadcrumbs.last
        selected = nil
    }

    func revealInFinder(_ node: ScanNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }
}
