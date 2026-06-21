import SwiftUI

// MARK: - SuiteCard
//
// The dashboard tool card: a gradient icon tile, title, blurb, and a custom live
// footer (the mini-stat). Hover lifts the card and lights its accent border.

struct SuiteCard<Footer: View>: View {
    let descriptor: ToolDescriptor
    let action: () -> Void
    @ViewBuilder var footer: () -> Footer

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    iconTile
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(descriptor.accent)
                        .opacity(hovering ? 1 : 0)
                        .offset(x: hovering ? 0 : -4, y: hovering ? 0 : 4)
                }

                Text(descriptor.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.primaryText)
                    .padding(.top, 14)

                Text(descriptor.blurb)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.secondaryText)
                    .lineSpacing(1.5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                Spacer(minLength: 14)

                Divider().background(Theme.border)
                    .padding(.bottom, 10)

                footer()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(hovering ? descriptor.accent.opacity(0.55) : Theme.border,
                            lineWidth: 1)
            )
            .shadow(color: hovering ? descriptor.accent.opacity(0.22) : .black.opacity(0.12),
                    radius: hovering ? 18 : 6, x: 0, y: hovering ? 8 : 3)
            .scaleEffect(hovering ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: hovering)
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(descriptor.linearGradient)
                .frame(width: 46, height: 46)
                .shadow(color: descriptor.accent.opacity(0.45), radius: 8, x: 0, y: 4)
            Image(systemName: descriptor.systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private var cardBackground: some View {
        ZStack {
            Theme.card
            descriptor.accent.opacity(hovering ? 0.06 : 0)
        }
    }
}

// MARK: - Card footer building blocks

/// A compact label + value used as a card footer (e.g. "CPU  12%").
struct CardStat: View {
    let label: String
    let value: String
    var accent: Color = Theme.primaryText

    var body: some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.secondaryText)
                .kerning(0.6)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(accent)
        }
    }
}

/// A thin progress meter for card footers (used % etc.).
struct CardMeter: View {
    let fraction: Double          // 0...1
    let gradient: [Color]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, geo.size.width * max(0, min(1, fraction))))
            }
        }
        .frame(height: 5)
    }
}

/// A "call to action" footer for tools without a live stat yet.
struct CardCallToAction: View {
    let text: String
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(accent)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(accent)
        }
    }
}
