import SwiftUI

@main
struct OpenDiskTestApp: App {
    @StateObject private var model = SuiteModel()

    var body: some Scene {
        WindowGroup {
            SuiteShell(model: model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }  // Disable the "New" menu item
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    model.updateChecker.checkForUpdate()
                }
                .keyboardShortcut("U", modifiers: [.command])
            }
        }

        // Disk-tool auxiliary windows (kept as detached windows).
        Window("Activity Log", id: "log") {
            LogWindowView(viewModel: model.diskVM)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 600, height: 400)

        Window("Benchmark History", id: "history") {
            HistoryView(viewModel: model.diskVM)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 460)

        Window("Sustained Write", id: "sustained") {
            SustainedView(viewModel: model.diskVM)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 460)
    }
}

// MARK: - SuiteShell
//
// Hosts the NavigationStack: the dashboard at the root, each tool pushed as a
// detail. Owns appearance application and the dashboard heartbeat lifecycle.

struct SuiteShell: View {
    @ObservedObject var model: SuiteModel
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    var body: some View {
        NavigationStack(path: $model.path) {
            DashboardView(model: model, updateChecker: model.updateChecker)
                .navigationDestination(for: ToolKind.self) { kind in
                    ToolDetailHost(model: model, kind: kind)
                }
        }
        .frame(minWidth: 880, minHeight: 600)
        .onAppear {
            applyAppearance()
            model.startHeartbeat()
            // Route update events into the disk tool's Activity Log.
            model.updateChecker.logHandler = { [weak model] message in
                model?.diskVM.addLog(message)
            }
            model.updateChecker.checkForUpdate()
            model.updateChecker.startPeriodicChecks()
        }
        .onChange(of: appearanceMode) { applyAppearance() }
    }

    private func applyAppearance() {
        switch appearanceMode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil // follow system
        }
    }
}
