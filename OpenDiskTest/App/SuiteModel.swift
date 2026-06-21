import SwiftUI
import Combine

// MARK: - SuiteModel
//
// App-level model for the suite shell. Owns the NavigationStack path, the
// long-lived tool view models that must stay alive off-screen (the disk VM, so
// its auxiliary windows keep working), the shared updater, and a low-frequency
// "dashboard heartbeat" that feeds the live mini-stats on the tool cards.

@MainActor
final class SuiteModel: ObservableObject {
    @Published var path: [ToolKind] = []

    // Long-lived tool view models.
    let diskVM: DiskSpeedTestViewModel
    let updateChecker: UpdateChecker

    // Live dashboard stats (updated on the heartbeat).
    @Published var cpuUsage: Double?          // 0...1
    @Published var memoryUsed: Double?        // 0...1
    @Published var homeVolumeUsedFraction: Double?  // 0...1

    private let cpuSampler = CPUUsageSampler()
    private var heartbeat: Timer?

    init() {
        self.diskVM = DiskSpeedTestViewModel()
        self.updateChecker = UpdateChecker()
        refreshHomeVolume()
    }

    func open(_ kind: ToolKind) {
        path.append(kind)
    }

    func goHome() {
        path.removeAll()
    }

    // MARK: Heartbeat

    func startHeartbeat() {
        guard heartbeat == nil else { return }
        tick()
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.5
        heartbeat = timer
    }

    func stopHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = nil
    }

    private func tick() {
        cpuUsage = cpuSampler.sample()
        let mem = MemoryStats.usage()
        memoryUsed = mem.total > 0 ? Double(mem.used) / Double(mem.total) : nil
    }

    /// Cheap free-space read for the home volume, for the Space/Cleanup cards.
    func refreshHomeVolume() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
           let total = values.volumeTotalCapacity, total > 0 {
            let available = values.volumeAvailableCapacityForImportantUsage ?? 0
            let used = Double(total) - Double(available)
            homeVolumeUsedFraction = max(0, min(1, used / Double(total)))
        }
    }
}
