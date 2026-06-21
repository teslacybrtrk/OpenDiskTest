import SwiftUI

// MARK: - Shared update UI
//
// The version badge and the "new version available" banner. Previously private
// to the disk view; promoted to shared chrome so the suite dashboard owns them.

/// Shows the running build (short commit SHA) plus the latest update-check status.
struct VersionBadge: View {
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        let (label, color, icon): (String, Color, String?) = {
            switch updateChecker.checkStatus {
            case .idle:            return ("", Theme.secondaryText, nil)
            case .checking:        return ("Checking…", Theme.secondaryText, nil)
            case .upToDate:        return ("Up to date", Color(hex: "3FB950"), "checkmark.circle.fill")
            case .updateAvailable: return ("Update available", Color(hex: "D29922"), "arrow.down.circle.fill")
            case .failed:          return ("Check failed", Color(hex: "F85149"), "exclamationmark.triangle.fill")
            }
        }()

        return HStack(spacing: 6) {
            Text("build \(String(BuildInfo.commitSHA.prefix(7)))")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if !label.isEmpty {
                HStack(spacing: 3) {
                    if let icon = icon {
                        Image(systemName: icon).font(.system(size: 9))
                    }
                    Text(label).font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(color)
            }
        }
        .help("Current build: \(BuildInfo.commitSHA)")
    }
}

/// The "a new version is available" banner with one-click update.
struct UpdateBanner: View {
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(LinearGradient(
                    colors: [Color(hex: "00BFFF"), Color(hex: "C84FFF")],
                    startPoint: .leading, endPoint: .trailing))

            VStack(alignment: .leading, spacing: 1) {
                Text("A new version is available")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                if !updateChecker.latestVersionName.isEmpty {
                    Text(updateChecker.latestVersionName)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                }
            }

            Spacer()

            if updateChecker.isDownloading || !updateChecker.statusMessage.isEmpty {
                if updateChecker.isDownloading {
                    ProgressView(value: updateChecker.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                        .tint(Color(hex: "00BFFF"))
                }
                Text(updateChecker.isDownloading
                     ? "\(Int(updateChecker.downloadProgress * 100))%"
                     : updateChecker.statusMessage)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.secondaryText)
                    .frame(minWidth: 36, alignment: .trailing)
            } else {
                Button { updateChecker.updateAvailable = false } label: {
                    Text("Dismiss")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(.plain)

                Button { updateChecker.performUpdate() } label: {
                    Text("Update & Relaunch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(LinearGradient(
                            colors: [Color(hex: "00BFFF"), Color(hex: "C84FFF")],
                            startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(updateChecker.releaseNotes.isEmpty
                      ? "Downloads and installs the new version, then relaunches automatically. If the app is in a read-only location, a ready-to-use copy is placed in your Downloads folder to drag over the old one instead."
                      : updateChecker.releaseNotes)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(hex: "1A1A2E"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: "00BFFF").opacity(0.25), lineWidth: 1))
    }
}
