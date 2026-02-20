import SwiftUI

@main
struct OpenDiskTestApp: App {
    @StateObject private var viewModel = DiskSpeedTestViewModel()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, updateChecker: updateChecker)
                .environmentObject(viewModel)
                .onAppear {
                    updateChecker.checkForUpdate()
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
    }
}
