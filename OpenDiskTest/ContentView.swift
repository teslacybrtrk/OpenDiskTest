import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject var viewModel: DiskSpeedTestViewModel
    @State private var showLog = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var windowHeight: CGFloat = 650 // Initial window height

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Disk Speed Test")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    HStack {
                        InputField(title: "File Size (MB)", value: $viewModel.fileSize)
                        InputField(title: "Iterations", value: Binding(
                            get: { Double(viewModel.iterations) },
                            set: { viewModel.iterations = Int($0) }
                        ))
                    }
                }
                
                Spacer()
                
                HStack(spacing: 20) {
                    IconButton(
                        icon: "play.fill",
                        color: Color(hex: "00A86B"),
                        action: viewModel.runTests,
                        disabled: viewModel.isRunning
                    )
                    
                    IconButton(
                        icon: "stop.fill",
                        color: Color(hex: "FF4136"),
                        action: viewModel.stopTests,
                        disabled: !viewModel.isRunning
                    )
                    
                    IconButton(
                        icon: "book.fill",
                        color: Color(hex: "0074D9"),
                        action: toggleLog
                    )
                }
            }

            HStack(spacing: 20) {
                ForEach(viewModel.results) { result in
                    VStack {
                        IndividualSpeedTestChart(result: result)
                            .frame(width: 200, height: 400)
                            .background(Color(hex: "2A2A2A"))
                            .cornerRadius(15)
                        
                        ResultBlock(result: result)
                    }
                }
            }

            Spacer()

            if showLog {
                IntegratedLogView(logs: $viewModel.logs, scrollProxy: $scrollProxy)
                    .frame(height: 200)
                    .transition(.move(edge: .bottom))
            }
        }
        .padding()
        .background(Color(hex: "1E1E1E"))
        .onChange(of: viewModel.logs) {
            scrollToBottom()
        }
        .frame(width: 920, height: windowHeight)
        .animation(.default, value: showLog)
    }
    
    private func scrollToBottom() {
        if showLog, let lastLog = viewModel.logs.last {
            scrollProxy?.scrollTo(lastLog, anchor: .bottom)
        }
    }

    private func toggleLog() {
        withAnimation {
            showLog.toggle()
            windowHeight = showLog ? 900 : 650
        }
    }
}

struct IntegratedLogView: View {
    @Binding var logs: [String]
    @Binding var scrollProxy: ScrollViewProxy?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(logs, id: \.self) { log in
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white)
                            .textSelection(.enabled)  // Make text selectable
                            .padding(.horizontal, 8)  // Add horizontal padding
                    }
                }
                .padding(.vertical, 8)  // Add vertical padding
            }
            .background(Color(hex: "2A2A2A"))
            .cornerRadius(10)
            .onAppear {
                scrollProxy = proxy
            }
        }
    }
}

struct InputField: View {
    let title: String
    @Binding var value: Double
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            TextField("", value: $value, formatter: NumberFormatter())
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 100)
        }
    }
}

struct IconButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    var disabled: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .cornerRadius(25)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

struct IndividualSpeedTestChart: View {
    let result: TestResult
    @State private var selectedDataPoint: (index: Int, speed: Double)?
    @State private var tooltipPosition: CGPoint?
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Chart {
                ForEach(Array(result.sortedSpeeds.enumerated()), id: \.offset) { index, speedData in
                    LineMark(
                        x: .value("Index", Double(index + 1) / Double(result.speeds.count + 1) * 100),
                        y: .value("Speed", speedData.element)
                    )
                    
                    PointMark(
                        x: .value("Index", Double(index + 1) / Double(result.speeds.count + 1) * 100),
                        y: .value("Speed", speedData.element)
                    )
                    .opacity(0.5)
                    .foregroundStyle(testColorScale[result.name] ?? .blue)
                    .symbol(.circle)
                    .symbolSize(30)
                    .accessibilityLabel("Test \(speedData.offset + 1)")
                    .accessibilityValue("\(String(format: "%.2f", speedData.element)) MB/s")
                    .accessibilityHidden(false)
                }
                
                RuleMark(y: .value("Min", result.minSpeed))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(alignment: .leading) {
                        Text("Min")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                
                RuleMark(y: .value("Avg", result.avgSpeed))
                    .foregroundStyle(.yellow)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(alignment: .leading) {
                        Text("Avg")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                
                RuleMark(y: .value("Max", result.maxSpeed))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(alignment: .leading) {
                        Text("Max")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: max(0, result.minSpeed * 0.9)...(result.maxSpeed * 1.1))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .foregroundStyle(Color.white)
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color(hex: "2A2A2A"))
                    .frame(height: 350)  // Adjust this value as needed
            }
            .padding(.horizontal, 10)  // Add horizontal padding
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    updateSelectedDataPoint(at: value.location, proxy: proxy, geometry: geometry)
                                }
                                .onEnded { _ in
                                    selectedDataPoint = nil
                                    tooltipPosition = nil
                                }
                        )
                }
            }
            
            if let dataPoint = selectedDataPoint, let position = tooltipPosition {
                tooltipView(for: dataPoint)
                    .position(x: position.x, y: position.y)
            }
        }
    }
    
    private var testColorScale: [String: Color] {
        [
            "Sequential Write": Color(hex: "FF851B"),
            "Sequential Read": Color(hex: "7FDBFF"),
            "Random Write": Color(hex: "B10DC9"),
            "Random Read": Color(hex: "2ECC40")
        ]
    }
    
    private func updateSelectedDataPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        
        let xPosition = location.x - geometry[plotFrame].origin.x
        let relativeXPosition = xPosition / geometry[plotFrame].width
        let index = Int(relativeXPosition * CGFloat(result.sortedSpeeds.count - 1))
        
        if index >= 0 && index < result.sortedSpeeds.count {
            let (originalIndex, speed) = result.sortedSpeeds[index]
            selectedDataPoint = (index: originalIndex, speed: speed)
            tooltipPosition = CGPoint(x: location.x, y: location.y - 40) // Offset tooltip above the cursor
        } else {
            selectedDataPoint = nil
            tooltipPosition = nil
        }
    }
    
    private func tooltipView(for dataPoint: (index: Int, speed: Double)) -> some View {
        Text("Test \(dataPoint.index + 1): \(String(format: "%.2f", dataPoint.speed)) MB/s")
            .padding(6)
            .background(Color(hex: "4A4A4A"))
            .foregroundColor(.white)
            .cornerRadius(6)
    }
}

struct ResultBlock: View {
    let result: TestResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(result.name)
                .font(.headline)
                .foregroundColor(.white)
            Text("Min: \(String(format: "%.2f", result.minSpeed)) MB/s")
                .foregroundColor(.gray)
            Text("Avg: \(String(format: "%.2f", result.avgSpeed)) MB/s")
                .foregroundColor(.gray)
            Text("Max: \(String(format: "%.2f", result.maxSpeed)) MB/s")
                .foregroundColor(.gray)
        }
        .padding()
        .frame(width: 200)
        .background(Color(hex: "2A2A2A"))
        .cornerRadius(10)
    }
}

struct LogView: View {
    @ObservedObject var viewModel: DiskSpeedTestViewModel

    var body: some View {
        VStack {
            List(viewModel.logs, id: \.self) { log in
                Text(log)
                    .foregroundColor(.white)
            }
            .background(Color(hex: "1E1E1E"))
        }
        .frame(minWidth: 480, minHeight: 300)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
