import SwiftUI
import Charts

// MARK: - SystemMonitorView
//
// Live CPU, memory, battery, and thermal/system cards. Owns its view model so
// sampling starts when the tool is shown and stops when it's dismissed.

struct SystemMonitorView: View {
    @StateObject private var vm = SystemMonitorViewModel()

    private let accent = [Color(hex: "00E676"), Color(hex: "00BFA5")]
    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 520), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                cpuCard
                memoryCard
                batteryCard
                systemCard
            }
            .padding(20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    // MARK: CPU

    private var cpuCard: some View {
        MonitorCard(title: "Processor", systemImage: "cpu", accent: accent) {
            HStack(alignment: .top, spacing: 18) {
                Gauge(fraction: vm.cpu?.aggregate ?? 0, gradient: accent,
                      centerText: "\(Int((vm.cpu?.aggregate ?? 0) * 100))%",
                      caption: "CPU")
                VStack(alignment: .leading, spacing: 8) {
                    Sparkline(values: vm.cpuHistory, gradient: accent)
                        .frame(height: 46)
                    perCoreGrid
                }
            }
        }
    }

    private var perCoreGrid: some View {
        let cores = vm.cpu?.perCore ?? []
        let cols = [GridItem(.adaptive(minimum: 26, maximum: 60), spacing: 5)]
        return LazyVGrid(columns: cols, spacing: 5) {
            ForEach(Array(cores.enumerated()), id: \.offset) { _, load in
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.1))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: accent, startPoint: .bottom, endPoint: .top))
                            .frame(height: max(2, geo.size.height * load))
                    }
                }
                .frame(height: 28)
            }
        }
    }

    // MARK: Memory

    private var memoryCard: some View {
        let m = vm.memory
        let usedFraction = m.total > 0 ? Double(m.used) / Double(m.total) : 0
        return MonitorCard(title: "Memory", systemImage: "memorychip", accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(bytes(m.used)) used")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.primaryText)
                    Spacer()
                    Text("of \(bytes(m.total))")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                }
                SegmentedBar(segments: [
                    .init(value: Double(m.wired), color: Color(hex: "00BFA5"), label: "Wired"),
                    .init(value: Double(m.active), color: Color(hex: "00E676"), label: "Active"),
                    .init(value: Double(m.compressed), color: Color(hex: "D29922"), label: "Compressed"),
                    .init(value: Double(m.free), color: Color.primary.opacity(0.12), label: "Free")
                ])
                Sparkline(values: vm.memHistory, gradient: accent)
                    .frame(height: 40)
                HStack(spacing: 14) {
                    legend(Color(hex: "00BFA5"), "Wired", bytes(m.wired))
                    legend(Color(hex: "00E676"), "Active", bytes(m.active))
                    legend(Color(hex: "D29922"), "Comp.", bytes(m.compressed))
                }
                if vm.swapTotal > 0 {
                    CardStat(label: "Swap used", value: bytes(vm.swapUsed))
                }
                let _ = usedFraction
            }
        }
    }

    // MARK: Battery

    @ViewBuilder
    private var batteryCard: some View {
        MonitorCard(title: "Battery", systemImage: "battery.100", accent: accent) {
            if vm.battery.isPresent {
                let b = vm.battery
                HStack(alignment: .top, spacing: 18) {
                    Gauge(fraction: b.charge, gradient: batteryGradient(b),
                          centerText: "\(Int(b.charge * 100))%",
                          caption: b.isCharging ? "Charging" : (b.isPluggedIn ? "Plugged in" : "On battery"))
                    VStack(alignment: .leading, spacing: 9) {
                        if let h = b.healthPercent { kv("Health", "\(h)%") }
                        if let c = b.cycleCount { kv("Cycles", "\(c)") }
                        if let cond = b.condition { kv("Condition", cond) }
                        if let t = b.timeToEmptyMinutes { kv("Time left", timeString(t)) }
                        if let t = b.timeToFullMinutes { kv("To full", timeString(t)) }
                    }
                    Spacer()
                }
            } else {
                emptyNote("No battery", "This Mac runs on AC power.", "powerplug")
            }
        }
    }

    private func batteryGradient(_ b: BatteryInfo) -> [Color] {
        if b.charge < 0.2 && !b.isCharging { return [Color(hex: "F85149"), Color(hex: "FF8C42")] }
        return accent
    }

    // MARK: System / thermal

    private var systemCard: some View {
        MonitorCard(title: "System", systemImage: "desktopcomputer", accent: accent) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Text("THERMAL")
                        .font(.system(size: 9, weight: .bold)).kerning(0.6)
                        .foregroundColor(Theme.secondaryText)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(vm.thermal.color).frame(width: 7, height: 7)
                        Text(vm.thermal.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(vm.thermal.color)
                    }
                    if vm.lowPowerMode {
                        Text("Low Power")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "D29922"))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: "D29922").opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Divider().background(Theme.border)
                kv("Model", vm.modelIdentifier)
                kv("Cores", "\(vm.coreCount) logical")
                kv("Memory", bytes(vm.totalRAM))
                kv("macOS", shortOS(vm.osVersion))
                kv("Uptime", uptimeString(vm.uptime))
            }
        }
    }

    // MARK: Helpers

    private func kv(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.system(size: 11)).foregroundColor(Theme.secondaryText)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.primaryText)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    private func legend(_ color: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 9)).foregroundColor(Theme.secondaryText)
                Text(value).font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.primaryText)
            }
        }
    }

    private func emptyNote(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 22)).foregroundColor(Theme.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.primaryText)
                Text(subtitle).font(.system(size: 11)).foregroundColor(Theme.secondaryText)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func bytes(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory)
    }
    private func timeString(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    private func uptimeString(_ t: TimeInterval) -> String {
        let total = Int(t)
        let d = total / 86400, h = (total % 86400) / 3600, m = (total % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
    private func shortOS(_ s: String) -> String {
        s.replacingOccurrences(of: "Version ", with: "")
    }
}

// MARK: - Reusable monitor pieces

struct MonitorCard<Content: View>: View {
    let title: String
    let systemImage: String
    let accent: [Color]
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: accent, startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.primaryText)
                Spacer()
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

/// A circular progress gauge with a centered value.
struct Gauge: View {
    let fraction: Double
    let gradient: [Color]
    let centerText: String
    var caption: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, fraction)))
                    .stroke(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: fraction)
                Text(centerText)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.primaryText)
            }
            .frame(width: 84, height: 84)
            if let caption {
                Text(caption).font(.system(size: 10, weight: .medium)).foregroundColor(Theme.secondaryText)
            }
        }
    }
}

/// A filled line sparkline over a 0...1 series.
struct Sparkline: View {
    let values: [Double]
    let gradient: [Color]

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            LineMark(x: .value("t", index), y: .value("v", value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                .lineStyle(StrokeStyle(lineWidth: 2))
            AreaMark(x: .value("t", index), y: .value("v", value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [gradient.first!.opacity(0.25), .clear],
                                                startPoint: .top, endPoint: .bottom))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .chartLegend(.hidden)
    }
}

/// A horizontal stacked bar (memory composition).
struct SegmentedBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let value: Double
        let color: Color
        let label: String
    }
    let segments: [Segment]

    var body: some View {
        GeometryReader { geo in
            let total = max(1, segments.reduce(0) { $0 + $1.value })
            HStack(spacing: 1.5) {
                ForEach(segments) { seg in
                    Rectangle()
                        .fill(seg.color)
                        .frame(width: max(0, geo.size.width * (seg.value / total)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 12)
    }
}
