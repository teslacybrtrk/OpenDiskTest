import Foundation
import SwiftUI

@MainActor
class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0

    private var assetURL: URL?
    private let repo = "teslacybrtrk/OpenDiskTest"

    func checkForUpdate() {
        // Use the standard latest-release endpoint (works regardless of tag name "latest")
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            // Extract SHA from release title like "Latest Build (abc1234)"
            guard let title = json["name"] as? String else { return }
            guard let regex = try? NSRegularExpression(pattern: "\\(([0-9a-f]{7,})\\)"),
                  let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let shaRange = Range(match.range(at: 1), in: title) else { return }
            let remoteSHA = String(title[shaRange])

            // Find the zip asset download URL (still recorded for future-proofing)
            var zipURL: URL?
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String, name.hasSuffix(".zip"),
                       let urlStr = asset["browser_download_url"] as? String {
                        zipURL = URL(string: urlStr)
                        break
                    }
                }
            }

            let localSHA = BuildInfo.commitSHA
            let isNew = !localSHA.hasPrefix(remoteSHA) && !remoteSHA.hasPrefix(localSHA)

            DispatchQueue.main.async {
                guard let self = self else { return }
                if isNew, let url = zipURL {
                    self.assetURL = url
                    self.updateAvailable = true
                }
            }
        }.resume()
    }

    /// Softened update action: opens the GitHub Releases page in the browser so the user
    /// can manually download the new .zip and replace the app. This eliminates the previous
    /// destructive in-place rm/mv auto-install (which was fragile and risky).
    func performUpdate() {
        let releasesURL = URL(string: "https://github.com/\(repo)/releases/latest")!
        NSWorkspace.shared.open(releasesURL)
        // Dismiss the banner after the user acts (they can re-check later)
        updateAvailable = false
        // Clear any stale download state (kept for banner compatibility)
        isDownloading = false
        downloadProgress = 0
    }
}
