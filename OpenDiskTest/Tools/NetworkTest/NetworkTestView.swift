import SwiftUI
import Charts

// MARK: - NetworkTestView

struct NetworkTestView: View {
    @StateObject private var vm = NetworkTestViewModel()

    private let accent = [Color(hex: "4F8DFD"), Color(hex: "8B5CF6")]
    private let downColor = Color(hex: "4F8DFD")
    private let upColor = Color(hex: "8B5CF6")

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                graphCard
                statsRow
                caption
            }
            .padding(20)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .onDisappear { vm.cancel() }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(spacing: 16) {
            Text(vm.phase.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(vm.isRunning ? accent[0] : Theme.secondaryText)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headlineValue)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: accent, startPoint: .leading, endPoint: .trailing))
                    .contentTransition(.numericText())
                Text("Mbps")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
            }
            .animation(.easeOut(duration: 0.2), value: headlineValue)

            if vm.isRunning && (vm.phase == .download || vm.phase == .upload) {
                ProgressView(value: vm.phaseProgress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 280)
                    .tint(vm.phase == .upload ? upColor : downColor)
            }

            Button(action: { vm.isRunning ? vm.cancel() : vm.start() }) {
                HStack(spacing: 7) {
                    Image(systemName: vm.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(vm.isRunning ? "Stop" : (vm.phase == .finished ? "Test Again" : "Start Test"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 22).padding(.vertical, 9)
                .background(
                    vm.isRunning
                    ? AnyShapeStyle(Color(hex: "E53935"))
                    : AnyShapeStyle(LinearGradient(colors: accent, startPoint: .leading, endPoint: .trailing))
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var headlineValue: String {
        if vm.isRunning && (vm.phase == .download || vm.phase == .upload) {
            return String(format: "%.0f", vm.liveMbps)
        }
        if let d = vm.downloadMbps { return String(format: "%.0f", d) }
        return "0"
    }

    // MARK: Graph

    private var graphCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                legend(downColor, "Download")
                legend(upColor, "Upload")
                Spacer()
            }
            Chart {
                ForEach(vm.downloadSamples) { s in
                    AreaMark(x: .value("t", s.t), y: .value("mbps", s.mbps), series: .value("k", "down"))
                        .foregroundStyle(LinearGradient(colors: [downColor.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("t", s.t), y: .value("mbps", s.mbps), series: .value("k", "down"))
                        .foregroundStyle(downColor)
                        .interpolationMethod(.catmullRom)
                }
                ForEach(vm.uploadSamples) { s in
                    LineMark(x: .value("t", s.t), y: .value("mbps", s.mbps), series: .value("k", "up"))
                        .foregroundStyle(upColor)
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(Theme.secondaryText)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 180)
            .overlay {
                if vm.downloadSamples.isEmpty && vm.uploadSamples.isEmpty {
                    Text("Run a test to see live throughput")
                        .font(.system(size: 12)).foregroundColor(Theme.secondaryText)
                }
            }
        }
        .padding(18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile("Download", vm.downloadMbps.map { String(format: "%.0f", $0) } ?? "—", "Mbps", downColor, "arrow.down")
            statTile("Upload", vm.uploadMbps.map { String(format: "%.0f", $0) } ?? "—", "Mbps", upColor, "arrow.up")
            statTile("Latency", vm.latencyMs.map { String(format: "%.0f", $0) } ?? "—", "ms", Color(hex: "00C9A7"), "timer")
            statTile("Jitter", vm.jitterMs.map { String(format: "%.1f", $0) } ?? "—", "ms", Color(hex: "D29922"), "waveform.path")
        }
    }

    private func statTile(_ label: String, _ value: String, _ unit: String, _ color: Color, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundColor(color)
                Text(label.uppercased()).font(.system(size: 9, weight: .bold)).kerning(0.5).foregroundColor(Theme.secondaryText)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(Theme.primaryText)
                Text(unit).font(.system(size: 10)).foregroundColor(Theme.secondaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var caption: some View {
        HStack(spacing: 5) {
            Image(systemName: "cloud.fill").font(.system(size: 9)).foregroundColor(Theme.secondaryText)
            Text(vm.colo != nil ? "Measured against Cloudflare · \(vm.colo!)" : "Measured against Cloudflare")
                .font(.system(size: 10)).foregroundColor(Theme.secondaryText)
        }
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(Theme.secondaryText)
        }
    }
}
