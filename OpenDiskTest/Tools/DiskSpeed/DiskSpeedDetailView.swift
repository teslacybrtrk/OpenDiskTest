import SwiftUI
import Charts
import UniformTypeIdentifiers
import AppKit

// MARK: - Disk Speed Detail View
//
// The full Disk Speed Test tool. Formerly the app's root `ContentView`; now one
// tool within the suite, hosted by the dashboard shell. `Theme` and `Color(hex:)`
// live in Core/.

struct DiskSpeedDetailView: View {
    @ObservedObject var viewModel: DiskSpeedTestViewModel
    @Environment(\.openWindow) private var openWindow

    @State private var isChoosingLocation = false
    @State private var didCopyResults = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            if viewModel.verifying || viewModel.verifyResult != nil {
                verifyBanner
            }

            Divider().background(Theme.border)

            ScrollView {
                resultsSection
                    .padding(20)
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.background)
        .frame(minWidth: 720, minHeight: 480)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRunning)
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentIteration > 0)
        .fileImporter(
            isPresented: $isChoosingLocation,
            allowedContentTypes: [UTType.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Start accessing now; the VM will create a long-lived bookmark
                    _ = url.startAccessingSecurityScopedResource()
                    viewModel.chooseTestDirectory(url)
                }
            case .failure(let error):
                // Errors are logged inside the VM; surface minimally
                print("Location selection error: \(error)")
            }
        }
    }

    // MARK: Verify Banner

    private var verifyBanner: some View {
        HStack(spacing: 12) {
            if viewModel.verifying {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "00BFFF"))
                Text("Verifying integrity…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                ProgressView(value: viewModel.verifyProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 160)
                    .tint(Color(hex: "00BFFF"))
                Text("\(Int(viewModel.verifyProgress * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.secondaryText)
                Button { viewModel.stopVerify() } label: {
                    Text("Stop").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Image(systemName: viewModel.verifyPassed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.system(size: 15))
                    .foregroundColor(viewModel.verifyPassed ? Color(hex: "3FB950") : Color(hex: "F85149"))
                Text(viewModel.verifyResult ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button { viewModel.dismissVerifyResult() } label: {
                    Text("Dismiss").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color(hex: "151515"))
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disk Speed Test")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.primaryText)
                    Text("Sequential & random read/write benchmark")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                }

                Spacer()

                // Disk-specific secondary tools.
                HStack(spacing: 8) {
                    toolButton(icon: "checkmark.shield", label: "Verify",
                               disabled: viewModel.isRunning || viewModel.sustainedRunning || viewModel.verifying,
                               action: viewModel.verifyIntegrity)
                    toolButton(icon: "waveform.path.ecg", label: "Sustained",
                               action: { openWindow(id: "sustained") })
                    toolButton(icon: "clock.arrow.circlepath", label: "History",
                               action: { openWindow(id: "history") })
                    toolButton(icon: "doc.text", label: "Log",
                               action: { openWindow(id: "log") })
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Divider().background(Theme.border)

            configPanel
            driveTargetCard

            // Progress bar (visible once any test has started)
            if viewModel.isRunning || viewModel.currentIteration > 0 {
                progressBar
            }
        }
    }

    // Compact secondary-tool button used in the app bar.
    private func toolButton(icon: String, label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(Theme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
        .help(label)
    }

    // MARK: Configuration panel

    private var configPanel: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 16) {
                InputField(title: "File Size (MB)", value: $viewModel.fileSize)
                InputField(title: "Iterations", value: Binding(
                    get: { Double(viewModel.iterations) },
                    set: { viewModel.iterations = Int($0) }
                ))
                labeledControl("Block Size") {
                    Picker("", selection: $viewModel.blockSizeKB) {
                        ForEach(DiskSpeedTestViewModel.blockSizeOptions, id: \.self) { kb in
                            Text(kb >= 1024 ? "\(kb / 1024) MB" : "\(kb) KB").tag(kb)
                        }
                    }
                    .pickerStyle(.segmented).frame(width: 150).labelsHidden()
                }
                labeledControl("Queue Depth") {
                    Picker("", selection: $viewModel.queueDepth) {
                        ForEach(DiskSpeedTestViewModel.queueDepthOptions, id: \.self) { qd in
                            Text("QD\(qd)").tag(qd)
                        }
                    }
                    .pickerStyle(.menu).frame(width: 78).labelsHidden()
                }
                labeledControl("Cache") {
                    Toggle(isOn: $viewModel.bypassCache) {
                        Text("Bypass (F_NOCACHE)").font(.system(size: 11))
                    }
                    .toggleStyle(.checkbox)
                    .help("Disable the OS file cache so results reflect true disk speed instead of RAM.")
                }
                Spacer()
            }
            .disabled(viewModel.isRunning)

            Divider().background(Theme.border)

            HStack(spacing: 10) {
                Text("Presets")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                ForEach(BenchmarkPreset.all) { preset in
                    Button { viewModel.applyPreset(preset) } label: {
                        Text(preset.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.primaryText)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(viewModel.isRunning)
                    .help("File \(String(format: "%.0f", preset.fileSizeMB)) MB · \(preset.iterations)× · \(preset.blockSizeKB) KB · QD\(preset.queueDepth)")
                }

                Spacer()

                if viewModel.isRunning {
                    ControlButton(icon: "stop.fill", label: "Stop", color: Color(hex: "E53935"),
                                  disabled: false, action: viewModel.stopTests)
                } else {
                    ControlButton(icon: "play.fill", label: "Run", color: Color(hex: "00C9A7"),
                                  disabled: !viewModel.canStartTests, action: viewModel.runTests)
                }
            }
        }
        .padding(18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// A label-on-top control cell for the config panel.
    private func labeledControl<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.secondaryText)
                .kerning(0.8)
            content()
        }
    }

    @ViewBuilder
    // MARK: Drive + target card

    private var driveTargetCard: some View {
        HStack(spacing: 14) {
            let info = viewModel.driveInfo
            Image(systemName: info?.isSolidState == false ? "externaldrive.fill" : "internaldrive.fill")
                .font(.system(size: 16))
                .foregroundStyle(LinearGradient(
                    colors: [Color(hex: "00BFFF"), Color(hex: "C84FFF")],
                    startPoint: .topLeading, endPoint: .bottomTrailing))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(info?.volumeName ?? "Disk")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.primaryText)
                        .lineLimit(1)
                    if let info = info {
                        ForEach(driveTags(info), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Theme.secondaryText)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.primary.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    if let model = info?.mediaName {
                        Text(model)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                // Location chooser
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.secondaryText)
                    Text(viewModel.testDirectory?.path ?? "System temp directory")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1).truncationMode(.middle)
                    Button { isChoosingLocation = true } label: {
                        Text("change").font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(hex: "00BFFF"))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Choose a custom test directory or volume")
                    if viewModel.testDirectory != nil {
                        Button { viewModel.resetToTemporaryDirectory() } label: {
                            Text("reset").font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Theme.secondaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Reset to system temporary directory")
                    }
                }
            }

            Spacer()

            if let info = info, info.totalBytes > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(byteString(info.freeBytes)) free of \(byteString(info.totalBytes))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.1))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Color(hex: "00BFFF"), Color(hex: "C84FFF")],
                                    startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(2, geo.size.width * info.usedFraction))
                        }
                    }
                    .frame(width: 130, height: 5)
                }
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func driveTags(_ info: DriveInfo) -> [String] {
        var tags: [String] = []
        if let kind = info.mediaKind { tags.append(kind) }
        if let conn = info.connection, !conn.isEmpty { tags.append(conn) }
        tags.append(info.fileSystem)
        return tags
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Results")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.secondaryText)
                        Spacer()
                        exportPNGButton
                        copyResultsButton
                    }
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(viewModel.results) { result in
                            TestCard(result: result, isLive: viewModel.isRunning)
                        }
                    }
                }
            }
        }
    }

    private var copyResultsButton: some View {
        Button {
            copyResults()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: didCopyResults ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                Text(didCopyResults ? "Copied" : "Copy Results")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(didCopyResults ? Color(hex: "3FB950") : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                didCopyResults
                    ? AnyShapeStyle(Color.white.opacity(0.08))
                    : AnyShapeStyle(LinearGradient(
                        colors: [Color(hex: "00BFFF"), Color(hex: "C84FFF")],
                        startPoint: .leading, endPoint: .trailing))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(viewModel.isRunning || !viewModel.hasResults)
        .help("Copy a shareable text summary of these results to the clipboard")
    }

    private var exportPNGButton: some View {
        Button {
            exportPNG()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "photo")
                    .font(.system(size: 10, weight: .semibold))
                Text("Export PNG")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(Theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(viewModel.isRunning || !viewModel.hasResults)
        .help("Save a shareable PNG image of these results to your Downloads folder")
    }

    /// Off-screen view rendered to an image for PNG export.
    private var resultsExportView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(hex: "00BFFF"), Color(hex: "C84FFF")],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("OpenDiskTest")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.primaryText)
                Spacer()
                Text(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
            if let info = viewModel.driveInfo {
                Text("\(info.volumeName) · \(info.mediaKind ?? "—") · \(info.connection ?? "—") · \(info.fileSystem)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.primaryText)
            }
            Text("\(String(format: "%.0f", viewModel.fileSize)) MB · \(viewModel.iterations) iterations · \(viewModel.blockSizeKB) KB block · cache \(viewModel.bypassCache ? "bypassed" : "enabled")")
                .font(.system(size: 11))
                .foregroundColor(Theme.secondaryText)
            HStack(alignment: .top, spacing: 16) {
                ForEach(viewModel.results) { result in
                    TestCard(result: result)
                }
            }
        }
        .padding(24)
        .background(Theme.background)
        .frame(width: 1000)
    }

    @MainActor
    private func exportPNG() {
        let renderer = ImageRenderer(content: resultsExportView)
        renderer.scale = 2
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]),
              let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            viewModel.addLog("PNG export failed")
            return
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let url = downloads.appendingPathComponent("OpenDiskTest-\(stamp).png")
        do {
            try png.write(to: url)
            viewModel.addLog("Exported results PNG to Downloads: \(url.lastPathComponent)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            viewModel.addLog("PNG export failed: \(error.localizedDescription)")
        }
    }

    private func copyResults() {
        let report = viewModel.resultsReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        viewModel.addLog("Results copied to clipboard")
        didCopyResults = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            didCopyResults = false
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

}

// MARK: - Log Window

struct LogWindowView: View {
    @ObservedObject var viewModel: DiskSpeedTestViewModel

    var body: some View {
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
        }
        .background(Theme.background)
        .frame(minWidth: 400, minHeight: 200)
    }
}

// MARK: - History

struct HistoryView: View {
    @ObservedObject var viewModel: DiskSpeedTestViewModel

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                Text("Benchmark History")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                Spacer()
                if !viewModel.history.isEmpty {
                    Text("\(viewModel.history.count) run\(viewModel.history.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                    Button {
                        viewModel.clearHistory()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().background(Theme.border)

            if viewModel.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 36))
                        .foregroundColor(Color(hex: "2C2C2C"))
                    Text("No saved runs yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "4A4A4A"))
                    Text("Completed benchmarks are saved here automatically")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "333333"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.history) { run in
                            HistoryRow(run: run, dateFormatter: Self.dateFormatter)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Theme.background)
        .frame(minWidth: 520, minHeight: 300)
    }
}

private struct HistoryRow: View {
    let run: BenchmarkRun
    let dateFormatter: DateFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(dateFormatter.string(from: run.date))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.primaryText)
                if let vol = run.volumeName {
                    Text(vol)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                }
                if let kind = run.mediaKind {
                    Text(kind)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
                Text("build \(run.build)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.secondaryText)
            }

            Text(run.configSummary)
                .font(.system(size: 10))
                .foregroundColor(Theme.secondaryText)

            HStack(spacing: 0) {
                ForEach(run.entries, id: \.name) { entry in
                    VStack(spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1)
                        Text(String(format: "%.1f", entry.avgMBps))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.color(for: entry.name))
                        Text(entry.avgIOPS.map { String(format: "%.0f IOPS", $0) } ?? "MB/s")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.secondaryText)
                        if let p99 = entry.p99LatencyMs {
                            Text(String(format: "%.2f ms p99", p99))
                                .font(.system(size: 8))
                                .foregroundColor(Theme.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Sustained write

struct SustainedView: View {
    @ObservedObject var viewModel: DiskSpeedTestViewModel

    private var accent: Color { Color(hex: "00BFFF") }

    private var yMax: Double {
        (viewModel.sustainedSamples.map { $0.mbps }.max() ?? 100) * 1.15
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                Text("Sustained Write")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)

                Spacer()

                Picker("", selection: $viewModel.sustainedDuration) {
                    ForEach(DiskSpeedTestViewModel.sustainedDurationOptions, id: \.self) { s in
                        Text("\(s)s").tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .disabled(viewModel.sustainedRunning)

                if viewModel.sustainedRunning {
                    ControlButton(icon: "stop.fill", label: "Stop", color: Color(hex: "E53935"),
                                  disabled: false, action: viewModel.stopSustainedWrite)
                } else {
                    ControlButton(icon: "play.fill", label: "Start", color: Color(hex: "00C9A7"),
                                  disabled: viewModel.isRunning, action: viewModel.startSustainedWrite)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().background(Theme.border)

            // Chart
            if viewModel.sustainedSamples.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 36))
                        .foregroundColor(Color(hex: "2C2C2C"))
                    Text("Run a sustained write to chart throughput over time")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "555555"))
                    Text("Reveals the SLC-cache cliff and thermal throttling")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "3A3A3A"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(viewModel.sustainedSamples) { sample in
                    AreaMark(x: .value("Time", sample.elapsed),
                             y: .value("MB/s", sample.mbps))
                        .foregroundStyle(LinearGradient(
                            colors: [accent.opacity(0.25), accent.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", sample.elapsed),
                             y: .value("MB/s", sample.mbps))
                        .foregroundStyle(accent)
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...max(1, yMax))
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Color(hex: "202020"))
                        AxisValueLabel().foregroundStyle(Theme.secondaryText).font(.system(size: 9))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Color(hex: "202020"))
                        AxisValueLabel().foregroundStyle(Theme.secondaryText).font(.system(size: 9))
                    }
                }
                .padding(16)
            }

            Divider().background(Theme.border)

            // Status
            HStack {
                Text(viewModel.sustainedStatus.isEmpty ? "Idle" : viewModel.sustainedStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(viewModel.sustainedStatus.localizedCaseInsensitiveContains("throttl")
                                     ? Color(hex: "D29922") : Theme.secondaryText)
                Spacer()
                if let last = viewModel.sustainedSamples.last {
                    Text(String(format: "%.0f MB/s @ %.0fs", last.mbps, last.elapsed))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.primaryText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Theme.background)
        .frame(minWidth: 520, minHeight: 320)
    }
}

// MARK: - TestCard

/// Pulsing "LIVE" indicator shown on a card while its test is running.
private struct LiveBadge: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: "3FB950"))
                .frame(width: 6, height: 6)
                .opacity(on ? 1 : 0.3)
            Text("LIVE")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color(hex: "3FB950"))
                .kerning(0.8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                on = true
            }
        }
    }
}

struct TestCard: View {
    let result: TestResult
    var isLive: Bool = false

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
                    .foregroundColor(Theme.primaryText)
                Spacer()
                if isLive {
                    LiveBadge()
                } else if !result.speeds.isEmpty {
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

            // IOPS + latency row (random tests only)
            if result.isRandom && !result.iopsSamples.isEmpty {
                Divider().background(Theme.border)
                HStack(spacing: 0) {
                    metric(label: "IOPS", value: String(format: "%.0f", result.avgIOPS), unit: "avg")
                    if result.hasLatency {
                        Rectangle().fill(Theme.border).frame(width: 1, height: 22)
                        metric(label: "LATENCY", value: String(format: "%.3f", result.avgLatency), unit: "ms avg")
                        Rectangle().fill(Theme.border).frame(width: 1, height: 22)
                        metric(label: "P99", value: String(format: "%.3f", result.p99Latency), unit: "ms")
                    }
                }
                .frame(height: 36)
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func metric(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Theme.secondaryText)
                .kerning(0.8)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(accent)
            Text(unit)
                .font(.system(size: 8))
                .foregroundColor(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
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
    var disabled: Bool = false
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
            .background(disabled ? Theme.border : color)
            .opacity(disabled ? 0.45 : 1.0)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
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
                .foregroundColor(Theme.primaryText)
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

