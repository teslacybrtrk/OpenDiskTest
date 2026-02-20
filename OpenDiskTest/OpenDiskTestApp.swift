import SwiftUI

@main
struct OpenDiskTestApp: App {
    @StateObject private var viewModel = DiskSpeedTestViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .environmentObject(viewModel)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }  // Disable the "New" menu item
        }

        Window("Activity Log", id: "log") {
            LogWindowView(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 600, height: 400)
    }
}
