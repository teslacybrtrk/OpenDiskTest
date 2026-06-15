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

    /// Downloads the latest update zip, extracts a ready-to-use "OpenDiskTest (new).app"
    /// into the user's Downloads folder, and reveals it in Finder. This is much more
    /// convenient than sending the user to the GitHub page while still being safe
    /// (no risky in-place replacement of the running app, which we avoid because the
    /// app is not code-signed/notarized).
    func performUpdate() {
        guard let assetURL = assetURL else { return }
        isDownloading = true
        downloadProgress = 0

        let delegate = DownloadDelegate { [weak self] progress in
            DispatchQueue.main.async { self?.downloadProgress = progress }
        } completion: { [weak self] tempFileURL, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isDownloading = false
                if let tempFileURL = tempFileURL, error == nil {
                    self.prepareDownloadedUpdate(from: tempFileURL)
                } else {
                    // Fallback: open the releases page
                    let releasesURL = URL(string: "https://github.com/\(self.repo)/releases/latest")!
                    NSWorkspace.shared.open(releasesURL)
                    self.updateAvailable = false
                }
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        session.downloadTask(with: assetURL).resume()
    }

    private func prepareDownloadedUpdate(from zipFile: URL) {
        let fm = FileManager.default
        guard let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            updateAvailable = false
            return
        }

        let finalZip = downloads.appendingPathComponent("OpenDiskTest.zip")

        do {
            // Overwrite any previous download
            if fm.fileExists(atPath: finalZip.path) {
                try fm.removeItem(at: finalZip)
            }
            try fm.moveItem(at: zipFile, to: finalZip)

            // Extract to a temp folder then pull out a clean ready-to-drag app bundle
            let extractDir = downloads.appendingPathComponent("OpenDiskTest-update-temp-\(UUID().uuidString)")
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", finalZip.path, extractDir.path]
            try ditto.run()
            ditto.waitUntilExit()

            var revealedItem = finalZip

            if ditto.terminationStatus == 0,
               let contents = try? fm.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil),
               let newApp = contents.first(where: { $0.pathExtension == "app" }) {

                let targetApp = downloads.appendingPathComponent("OpenDiskTest (new).app")
                if fm.fileExists(atPath: targetApp.path) {
                    try? fm.removeItem(at: targetApp)
                }
                try fm.moveItem(at: newApp, to: targetApp)

                // Clean up the temporary extract dir
                try? fm.removeItem(at: extractDir)

                revealedItem = targetApp
            }

            // Reveal the most useful thing (the ready .app if we got it, otherwise the zip)
            NSWorkspace.shared.activateFileViewerSelecting([revealedItem])

            updateAvailable = false
        } catch {
            // Last resort: reveal whatever we have and let the user handle it
            NSWorkspace.shared.activateFileViewerSelecting([finalZip])
            updateAvailable = false
        }
    }
}

// MARK: - Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    let onComplete: (URL?, Error?) -> Void

    init(onProgress: @escaping (Double) -> Void, completion: @escaping (URL?, Error?) -> Void) {
        self.onProgress = onProgress
        self.onComplete = completion
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move to a stable temp location
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("OpenDiskTest-\(UUID().uuidString).zip")
        try? FileManager.default.moveItem(at: location, to: dest)
        onComplete(dest, nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onComplete(nil, error)
        }
    }
}
