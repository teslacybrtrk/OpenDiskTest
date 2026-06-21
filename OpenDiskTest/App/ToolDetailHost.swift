import SwiftUI

// MARK: - ToolDetailHost
//
// Routes a ToolKind pushed onto the NavigationStack to its detail view. Tools
// not yet implemented render a polished placeholder. The NavigationStack supplies
// the back button and title bar.

struct ToolDetailHost: View {
    @ObservedObject var model: SuiteModel
    let kind: ToolKind

    var body: some View {
        Group {
            switch kind {
            case .diskSpeed:
                DiskSpeedDetailView(viewModel: model.diskVM)
            case .systemMonitor:
                SystemMonitorView()
            case .networkTest:
                NetworkTestView()
            default:
                ToolPlaceholderView(descriptor: kind.descriptor)
            }
        }
        .navigationTitle(kind.descriptor.title)
    }
}

// MARK: - Placeholder

struct ToolPlaceholderView: View {
    let descriptor: ToolDescriptor

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(descriptor.linearGradient)
                    .frame(width: 84, height: 84)
                    .shadow(color: descriptor.accent.opacity(0.4), radius: 16, x: 0, y: 8)
                Image(systemName: descriptor.systemImage)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(descriptor.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Theme.primaryText)
            Text(descriptor.blurb)
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill").font(.system(size: 10))
                Text("Coming together in this build")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(descriptor.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(descriptor.accent.opacity(0.12))
            .clipShape(Capsule())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
