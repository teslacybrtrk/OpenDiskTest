import SwiftUI

@main
struct OpenDiskTestApp: App {
    @StateObject private var viewModel = DiskSpeedTestViewModel()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            DiskSpeedDetailView(viewModel: viewModel, updateChecker: updateChecker)
                .environmentObject(viewModel)
                .onAppear {
                    // Route update events into the Activity Log so failures are diagnosable.
                    updateChecker.logHandler = { [weak viewModel] (message: String) in
                        viewModel?.addLog(message)
                    }
                    updateChecker.checkForUpdate()
                    updateChecker.startPeriodicChecks()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }  // Disable the "New" menu item
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateChecker.checkForUpdate()
                }
                .keyboardShortcut("U", modifiers: [.command])
            }
        }

        Window("Activity Log", id: "log") {
            LogWindowView(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 600, height: 400)

        Window("Benchmark History", id: "history") {
            HistoryView(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 460)

        Window("Sustained Write", id: "sustained") {
            SustainedView(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 460)
    }
}
