import SwiftUI
import AppKit

// MARK: - Theme
//
// The suite-wide neutral palette. Resolves to dark or light values based on the
// effective appearance. Tool-specific accent colors live on `ToolDescriptor`,
// not here — `testColors` below is the disk-benchmark's own per-test palette and
// should not be treated as a suite-level accent source.

enum Theme {
    /// A color that resolves to the dark or light hex depending on the effective appearance.
    private static func dynamic(dark: String, light: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }

    static let background    = dynamic(dark: "0D0D0D", light: "F2F2F4")
    static let card          = dynamic(dark: "181818", light: "FFFFFF")
    static let cardInner     = dynamic(dark: "111111", light: "ECECEE")
    static let border        = dynamic(dark: "2A2A2A", light: "D8D8DC")
    static let secondaryText = dynamic(dark: "6E6E6E", light: "8A8A8E")
    static let primaryText   = dynamic(dark: "F5F5F5", light: "1A1A1A")

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
