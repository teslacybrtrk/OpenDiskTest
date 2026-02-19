import SwiftUI
import Charts

// MARK: - Theme

private enum Theme {
    static let background    = Color(hex: "0D0D0D")
    static let card          = Color(hex: "181818")
    static let cardInner     = Color(hex: "111111")
    static let border        = Color(hex: "2A2A2A")
    static let secondaryText = Color(hex: "6E6E6E")

    static let testColors: [String: Color] = [
        "Sequential Write": Color(hex: "FF6B35"),
        "Sequential Read":  Color(hex: "00BFFF"),
        "Random Write":     Color(hex: "C84FFF"),
        "Random Read":      Color(hex: "00E676")
    ]

    static func color(for name: String) -> Color {
        testColors[name] ?? .blue
    }
}

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var viewModel: DiskSpeedTestViewModel
    @State private var showLog = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider().background(Theme.border)

            resultsSection
                .padding(20)

            if showLog {
                Divider().background(Theme.border)
                logSection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.background)
        .frame(width: 960)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showLog)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRunning)
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentIteration > 0)
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // Logo + title
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(hex: "2C2C2C"), Color(hex: "1A1A1A")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 42, height: 42)
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: "00BFFF"), Color(hex: "C84FFF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenDiskTest")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("macOS Disk Benchmark")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText)
                    }
                }

                Spacer()

                // Inputs
                HStack(spacing: 12) {
                    InputField(title: "File Size (MB)", value: $viewModel.fileSize)
                    InputField(title: "Iterations", value: Binding(
                        get: { Double(viewModel.iterations) },
                        set: { viewModel.iterations = Int($0) }
                    ))
                }

                Spacer()

                // Controls
                HStack(spacing: 10) {
                    if viewModel.isRunning {
                        ControlButton(
                            icon: "stop.fill",
                            label: "Stop",
                            color: Color(hex: "E53935"),
                            action: viewModel.stopTests
                        )
                    } else {
                        ControlButton(
                            icon: "play.fill",
                            label: "Run",
                            color: Color(hex: "00C9A7"),
                            action: viewModel.runTests
                        )
                    }
                    ControlButton(
                        icon: showLog ? "chevron.down.circle.fill" : "doc.text.fill",
                        label: "Log",
                        color: showLog ? Color(hex: "0A84FF") : Color(hex: "2C2C2C"),
                        action: { withAnimation { showLog.toggle() } }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // Progress bar (visible once any test has started)
            if viewModel.isRunning || viewModel.currentIteration > 0 {
                progressBar
            }
        }
    }

    private var progressBar: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: 2)
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "00BFFF"), Color(hex: "C84FFF")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * viewModel.progress, height: 2)
                        .animation(.linear(duration: 0.2), value: viewModel.progress)
                }
            }
            .frame(height: 2)

            HStack(spacing: 6) {
                if viewModel.isRunning {
                    Circle()
                        .fill(Color(hex: "00C9A7"))
                        .frame(width: 5, height: 5)
                    Text("Running  ·  Iteration \(viewModel.currentIteration) of \(viewModel.iterations)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                } else {
                    Text("Completed \(viewModel.currentIteration) of \(viewModel.iterations) iterations")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
    }

    // MARK: Results

    private var resultsSection: some View {
        Group {
            if viewModel.results.allSatisfy({ $0.speeds.isEmpty }) {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(viewModel.results) { result in
                        TestCard(result: result)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "internaldrive")
                .font(.system(size: 44))
                .foregroundColor(Color(hex: "2C2C2C"))
            Text("Ready to benchmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: "4A4A4A"))
            Text("Press Run to measure sequential and random read/write speeds")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "333333"))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
    }

    // MARK: Log

    private var logSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                Text("Activity Log")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                Spacer()
                Button {
                    viewModel.logs.removeAll()
                } label: {
                    Text("Clear")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().background(Theme.border)

            IntegratedLogView(logs: $viewModel.logs)
                .frame(height: 180)
        }
    }
}

// MARK: - TestCard

struct TestCard: View {
    let result: TestResult

    private var accent: Color { Theme.color(for: result.name) }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                Text(result.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if !result.speeds.isEmpty {
                    Text("\(result.speeds.count) run\(result.speeds.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Chart or waiting state
            if result.speeds.isEmpty {
                Theme.cardInner
                    .frame(height: 290)
                    .overlay(
                        Text("Waiting…")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "333333"))
                    )
            } else {
                SpeedDistributionChart(result: result)
                    .frame(height: 290)
                    .background(Theme.cardInner)
            }

            Divider().background(Theme.border)

            // Stats footer
            HStack(spacing: 0) {
                StatCell(label: "MIN", value: result.minSpeed, color: Color(hex: "FF5C5C"))
                Rectangle().fill(Theme.border).frame(width: 1)
                StatCell(label: "AVG", value: result.avgSpeed, color: accent)
                Rectangle().fill(Theme.border).frame(width: 1)
                StatCell(label: "MAX", value: result.maxSpeed, color: Color(hex: "5CFF8A"))
            }
            .frame(height: 58)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

struct StatCell: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.secondaryText)
                .kerning(1.2)
            Text(value > 0 ? String(format: "%.1f", value) : "—")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .contentTransition(.numericText())
            Text("MB/s")
                .font(.system(size: 9))
                .foregroundColor(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Chart

struct SpeedDistributionChart: View {
    let result: TestResult

    private var accent: Color { Theme.color(for: result.name) }

    private var yMin: Double { max(0, result.minSpeed * 0.85) }
    private var yMax: Double {
        let top = result.maxSpeed * 1.12
        return top > yMin ? top : yMin + 1
    }

    var body: some View {
        Chart {
            ForEach(Array(result.sortedSpeeds.enumerated()), id: \.offset) { index, speedData in
                let x = Double(index + 1) / Double(result.speeds.count + 1) * 100

                AreaMark(
                    x: .value("Percentile", x),
                    yStart: .value("Base", yMin),
                    yEnd: .value("Speed", speedData.element)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.25), accent.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Percentile", x),
                    y: .value("Speed", speedData.element)
                )
                .foregroundStyle(accent)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            // Average reference line
            RuleMark(y: .value("Avg", result.avgSpeed))
                .foregroundStyle(accent.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartXScale(domain: 0...100)
        .chartYScale(domain: yMin...yMax)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel()
                    .foregroundStyle(Theme.secondaryText)
                    .font(.system(size: 9))
                AxisGridLine()
                    .foregroundStyle(Color(hex: "202020"))
            }
        }
        .chartPlotStyle { plot in
            plot.background(Theme.cardInner)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }
}

// MARK: - Log

struct IntegratedLogView: View {
    @Binding var logs: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(logs.enumerated()), id: \.offset) { index, log in
                        logLine(log)
                            .id(index)
                    }
                }
                .padding(12)
            }
            .onChange(of: logs) {
                if let last = logs.indices.last {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
        .background(Color(hex: "090909"))
    }

    private func logLine(_ log: String) -> some View {
        let parts = log.split(separator: "]", maxSplits: 1)
        let timestamp = parts.count > 1 ? String(parts[0]) + "]" : ""
        let message   = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : log

        return HStack(alignment: .top, spacing: 8) {
            Text(timestamp)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(hex: "4A7A4A"))
            Text(message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(hex: "C0C0C0"))
                .textSelection(.enabled)
        }
    }
}

// MARK: - Controls

struct ControlButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct InputField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .kerning(0.3)
            TextField("", value: $value, formatter: NumberFormatter())
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 88)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(hex: "222222"))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.border, lineWidth: 1)
                )
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(.sRGB,
                  red:     Double(r) / 255,
                  green:   Double(g) / 255,
                  blue:    Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}
