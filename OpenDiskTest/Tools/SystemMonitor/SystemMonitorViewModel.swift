import SwiftUI
import Combine

// MARK: - SystemMonitorViewModel
//
// Samples cheap, public-API system metrics at 1 Hz into ring buffers for
// sparklines. Starts/stops with the view's lifetime so no sampling runs in the
// background. Temperature in °C is intentionally not shown: it requires private
// APIs on Apple Silicon. Apple's official `thermalState` is used instead.

@MainActor
final class SystemMonitorViewModel: ObservableObject {
    @Published var cpu: CPUReading?
    @Published var memory = MemoryStats.Breakdown()
    @Published var swapUsed: UInt64 = 0
    @Published var swapTotal: UInt64 = 0
    @Published var battery = BatteryInfo()
    @Published var thermal: ProcessInfo.ThermalState = .nominal
    @Published var lowPowerMode = false

    @Published var cpuHistory: [Double] = []
    @Published var memHistory: [Double] = []

    let historyLength = 80

    // Static host facts (read once).
    let coreCount = ProcessInfo.processInfo.processorCount
    let physicalCores = ProcessInfo.processInfo.activeProcessorCount
    let totalRAM = MemoryStats.totalBytes
    let hostName = Host.current().localizedName ?? "This Mac"
    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    let modelIdentifier = SystemMonitorViewModel.hardwareModel()

    private let cpuSampler = CPUUsageSampler()
    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?

    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() {
        guard timer == nil else { return }
        readThermal()
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.readThermal() }
            }
        tick() // prime
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.2
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let obs = thermalObserver {
            NotificationCenter.default.removeObserver(obs)
            thermalObserver = nil
        }
    }

    private func tick() {
        if let reading = cpuSampler.reading() {
            cpu = reading
            push(&cpuHistory, reading.aggregate)
        }
        memory = MemoryStats.breakdown()
        let memFraction = memory.total > 0 ? Double(memory.used) / Double(memory.total) : 0
        push(&memHistory, memFraction)

        let swap = SwapStats.usage()
        swapUsed = swap.used
        swapTotal = swap.total

        battery = Battery.read()
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func readThermal() {
        thermal = ProcessInfo.processInfo.thermalState
    }

    private func push(_ buffer: inout [Double], _ value: Double) {
        buffer.append(value)
        if buffer.count > historyLength {
            buffer.removeFirst(buffer.count - historyLength)
        }
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .nominal:  return Color(hex: "3FB950")
        case .fair:     return Color(hex: "D29922")
        case .serious:  return Color(hex: "FF8C42")
        case .critical: return Color(hex: "F85149")
        @unknown default: return Color(hex: "6E6E6E")
        }
    }
}
