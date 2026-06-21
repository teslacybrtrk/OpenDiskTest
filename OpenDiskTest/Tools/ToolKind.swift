import SwiftUI

// MARK: - Tool registry
//
// The suite is a set of tools presented on a dashboard. `ToolKind` is the stable
// identity used as the NavigationStack path element; `ToolDescriptor` carries the
// presentation metadata (title, icon, gradient accent, blurb). Accent gradients
// are owned here — deliberately separate from `Theme` (the neutral palette).

enum ToolKind: String, CaseIterable, Identifiable, Hashable {
    case diskSpeed
    case spaceAnalyzer
    case duplicateFinder
    case systemMonitor
    case networkTest
    case cleanup

    var id: String { rawValue }

    var descriptor: ToolDescriptor {
        switch self {
        case .diskSpeed:
            return ToolDescriptor(
                kind: self,
                title: "Disk Speed Test",
                blurb: "Benchmark sequential & random read/write throughput, IOPS, and latency.",
                systemImage: "speedometer",
                gradient: [Color(hex: "00BFFF"), Color(hex: "C84FFF")]
            )
        case .spaceAnalyzer:
            return ToolDescriptor(
                kind: self,
                title: "Space Analyzer",
                blurb: "See what's eating your storage with an interactive treemap.",
                systemImage: "chart.pie.fill",
                gradient: [Color(hex: "FF6B35"), Color(hex: "FF2D78")]
            )
        case .duplicateFinder:
            return ToolDescriptor(
                kind: self,
                title: "Duplicate Finder",
                blurb: "Hunt down duplicate and oversized files to reclaim space.",
                systemImage: "doc.on.doc.fill",
                gradient: [Color(hex: "00C9A7"), Color(hex: "00BFFF")]
            )
        case .systemMonitor:
            return ToolDescriptor(
                kind: self,
                title: "System Monitor",
                blurb: "Live CPU, memory, power, and battery health at a glance.",
                systemImage: "waveform.path.ecg",
                gradient: [Color(hex: "00E676"), Color(hex: "00BFA5")]
            )
        case .networkTest:
            return ToolDescriptor(
                kind: self,
                title: "Network Speed",
                blurb: "Measure download, upload, and latency against Cloudflare.",
                systemImage: "dot.radiowaves.up.forward",
                gradient: [Color(hex: "4F8DFD"), Color(hex: "8B5CF6")]
            )
        case .cleanup:
            return ToolDescriptor(
                kind: self,
                title: "Disk Cleanup",
                blurb: "Reclaim space from caches, logs, trash, and build artifacts.",
                systemImage: "sparkles",
                gradient: [Color(hex: "FFB300"), Color(hex: "FF6B35")]
            )
        }
    }
}

struct ToolDescriptor: Identifiable {
    let kind: ToolKind
    let title: String
    let blurb: String
    let systemImage: String
    /// Two-stop accent gradient (top-leading → bottom-trailing).
    let gradient: [Color]

    var id: String { kind.rawValue }
    var accent: Color { gradient.first ?? .accentColor }

    var linearGradient: LinearGradient {
        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
