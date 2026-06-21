import SwiftUI

// MARK: - DashboardView
//
// The suite home screen: branding + appearance + update status across the top,
// then a responsive grid of tool cards. Each card pushes its tool onto the
// NavigationStack. Live mini-stats are fed by the SuiteModel heartbeat.

struct DashboardView: View {
    @ObservedObject var model: SuiteModel
    @ObservedObject var updateChecker: UpdateChecker
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                topBar

                if updateChecker.updateAvailable {
                    UpdateBanner(updateChecker: updateChecker)
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(ToolKind.allCases) { kind in
                        card(for: kind)
                    }
                }

                footer
            }
            .padding(28)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "00BFFF"), Color(hex: "C84FFF")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .shadow(color: Color(hex: "00BFFF").opacity(0.4), radius: 8, x: 0, y: 4)
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("OpenDiskTest Suite")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.primaryText)
                HStack(spacing: 7) {
                    Text("Disk & system utilities")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                    VersionBadge(updateChecker: updateChecker)
                }
            }

            Spacer()

            Picker("", selection: $appearanceMode) {
                Image(systemName: "circle.lefthalf.filled").tag("system")
                Image(systemName: "sun.max").tag("light")
                Image(systemName: "moon.fill").tag("dark")
            }
            .pickerStyle(.segmented)
            .frame(width: 108)
            .help("Appearance: follow System, Light, or Dark")
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("Choose a tool to get started")
                .font(.system(size: 11))
                .foregroundColor(Theme.secondaryText)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: Cards

    @ViewBuilder
    private func card(for kind: ToolKind) -> some View {
        let d = kind.descriptor
        SuiteCard(descriptor: d, action: { model.open(kind) }) {
            cardFooter(for: kind, descriptor: d)
        }
    }

    @ViewBuilder
    private func cardFooter(for kind: ToolKind, descriptor d: ToolDescriptor) -> some View {
        switch kind {
        case .diskSpeed:
            if let last = model.diskVM.history.first, let top = last.entries.first {
                CardStat(label: "Last run",
                         value: String(format: "%.0f MB/s", top.avgMBps),
                         accent: d.accent)
            } else {
                CardCallToAction(text: "Run a benchmark", accent: d.accent)
            }

        case .systemMonitor:
            VStack(spacing: 7) {
                liveMeterRow(label: "CPU", fraction: model.cpuUsage, gradient: d.gradient)
                liveMeterRow(label: "RAM", fraction: model.memoryUsed, gradient: d.gradient)
            }

        case .spaceAnalyzer, .cleanup:
            if let used = model.homeVolumeUsedFraction {
                VStack(spacing: 6) {
                    CardStat(label: "Disk used", value: "\(Int(used * 100))%", accent: d.accent)
                    CardMeter(fraction: used, gradient: d.gradient)
                }
            } else {
                CardCallToAction(text: kind == .cleanup ? "Free up space" : "Analyze storage", accent: d.accent)
            }

        case .duplicateFinder:
            CardCallToAction(text: "Find duplicates", accent: d.accent)

        case .networkTest:
            CardCallToAction(text: "Test connection", accent: d.accent)
        }
    }

    @ViewBuilder
    private func liveMeterRow(label: String, fraction: Double?, gradient: [Color]) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.secondaryText)
                .frame(width: 26, alignment: .leading)
            CardMeter(fraction: fraction ?? 0, gradient: gradient)
            Text(fraction != nil ? "\(Int((fraction ?? 0) * 100))%" : "—")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.secondaryText)
                .frame(width: 32, alignment: .trailing)
        }
    }
}
