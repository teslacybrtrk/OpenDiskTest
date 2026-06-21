import Foundation
import SwiftUI

@MainActor
class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    /// Short status shown in the banner (e.g. "Downloading…", "Installing…").
    @Published var statusMessage = ""
    /// Human-readable name of the available release, e.g. "Latest Build (abc1234)".
    @Published var latestVersionName = ""
    /// Release notes (the GitHub release body), surfaced in the banner tooltip.
    @Published var releaseNotes = ""

    /// Routes update events into the app's Activity Log. Set by the app at launch.
    var logHandler: ((String) -> Void)?

    private var assetURL: URL?
    private let repo = "teslacybrtrk/OpenDiskTest"

    private func log(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.logHandler?("Update: \(message)")
        }
    }

    func checkForUpdate() {
        log("Checking for updates…")
        // Use the standard latest-release endpoint (works regardless of tag name "latest")
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.log("Check failed: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                self.log("Check failed: GitHub returned HTTP \(http.statusCode)")
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.log("Check failed: could not parse GitHub response")
                return
            }

            // Extract SHA from release title like "Latest Build (abc1234)"
            guard let title = json["name"] as? String else {
                self.log("Check failed: release has no title")
                return
            }
            guard let regex = try? NSRegularExpression(pattern: "\\(([0-9a-f]{7,})\\)"),
                  let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let shaRange = Range(match.range(at: 1), in: title) else {
                self.log("Check failed: no commit SHA found in release title \"\(title)\"")
                return
            }
            let remoteSHA = String(title[shaRange])
            let notes = (json["body"] as? String) ?? ""

            // Find the zip asset download URL
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
            // Rolling "latest" release model: any difference means a newer build is published.
            let isNew = !localSHA.hasPrefix(remoteSHA) && !remoteSHA.hasPrefix(localSHA)

            DispatchQueue.main.async {
                guard isNew else {
                    self.log("Up to date (\(localSHA.prefix(7)))")
                    return
                }
                guard let url = zipURL else {
                    self.log("New version \"\(title)\" available, but no .zip asset was attached")
                    return
                }
                self.assetURL = url
                self.latestVersionName = title
                self.releaseNotes = notes
                self.updateAvailable = true
                self.log("New version available: \(title)")
            }
        }.resume()
    }

    /// Downloads the latest update zip and installs it. When the running app lives in a
    /// writable location, it replaces itself in place and relaunches automatically — a
    /// one-click update with no Gatekeeper prompt (the download is performed by this
    /// non-sandboxed app, so the new bundle is never quarantined). If in-place replacement
    /// isn't possible (read-only location or App Translocation), it falls back to placing a
    /// ready-to-drag "OpenDiskTest (new).app" in Downloads and revealing it in Finder.
    func performUpdate() {
        guard let assetURL = assetURL else { return }
        isDownloading = true
        downloadProgress = 0
        statusMessage = "Downloading…"
        log("Downloading update…")

        let delegate = DownloadDelegate { [weak self] progress in
            DispatchQueue.main.async { self?.downloadProgress = progress }
        } completion: { [weak self] tempFileURL, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isDownloading = false
                if let tempFileURL = tempFileURL, error == nil {
                    self.installDownloadedUpdate(from: tempFileURL)
                } else {
                    self.log("Download failed: \(error?.localizedDescription ?? "unknown error"). Opening releases page.")
                    let releasesURL = URL(string: "https://github.com/\(self.repo)/releases/latest")!
                    NSWorkspace.shared.open(releasesURL)
                    self.statusMessage = ""
                    self.updateAvailable = false
                }
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        session.downloadTask(with: assetURL).resume()
    }

    private func installDownloadedUpdate(from zipFile: URL) {
        let fm = FileManager.default
        statusMessage = "Installing…"

        // Extract the downloaded zip into a private temp dir.
        let extractDir = fm.temporaryDirectory.appendingPathComponent("OpenDiskTest-update-\(UUID().uuidString)")
        guard let newApp = extractApp(from: zipFile, into: extractDir) else {
            log("Could not extract the update. Opening releases page.")
            statusMessage = ""
            updateAvailable = false
            NSWorkspace.shared.open(URL(string: "https://github.com/\(repo)/releases/latest")!)
            return
        }

        // Defensive: ensure the new bundle carries no quarantine flag.
        stripQuarantine(newApp)

        let currentApp = Bundle.main.bundleURL
        if canReplaceInPlace(currentApp) {
            replaceInPlaceAndRelaunch(newApp: newApp, currentApp: currentApp)
        } else {
            log("App location is read-only; falling back to manual drag-to-update.")
            revealForManualInstall(newApp: newApp, extractDir: extractDir)
        }
    }

    /// Extracts the first .app bundle found in the zip. Returns its URL inside `extractDir`.
    private func extractApp(from zipFile: URL, into extractDir: URL) -> URL? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zipFile.path, extractDir.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0,
                  let contents = try? fm.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil),
                  let app = contents.first(where: { $0.pathExtension == "app" }) else {
                return nil
            }
            return app
        } catch {
            log("Extraction error: \(error.localizedDescription)")
            return nil
        }
    }

    /// True when we can safely swap the running bundle: it isn't App-Translocated and its
    /// parent directory is writable by the current user.
    private func canReplaceInPlace(_ currentApp: URL) -> Bool {
        let path = currentApp.path
        if path.contains("/AppTranslocation/") {
            return false
        }
        let parent = currentApp.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: parent.path)
    }

    private func replaceInPlaceAndRelaunch(newApp: URL, currentApp: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        // Helper waits for this app to quit, swaps the bundle, clears quarantine, relaunches.
        let script = """
        #!/bin/sh
        APP_PID="$1"
        NEW="$2"
        DEST="$3"
        while /bin/kill -0 "$APP_PID" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/sleep 0.3
        /bin/rm -rf "$DEST"
        /bin/mv "$NEW" "$DEST"
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        /usr/bin/open "$DEST"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("odt-update-\(UUID().uuidString).sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            log("Could not stage updater; falling back to manual install.")
            revealForManualInstall(newApp: newApp, extractDir: newApp.deletingLastPathComponent())
            return
        }

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [scriptURL.path, String(pid), newApp.path, currentApp.path]
        do {
            try helper.run()
        } catch {
            log("Could not launch updater; falling back to manual install.")
            revealForManualInstall(newApp: newApp, extractDir: newApp.deletingLastPathComponent())
            return
        }

        statusMessage = "Restarting…"
        log("Installing update and relaunching…")
        // Give the log a beat to flush, then quit so the helper can swap the bundle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    /// Fallback: place a ready-to-use "OpenDiskTest (new).app" in Downloads and reveal it.
    private func revealForManualInstall(newApp: URL, extractDir: URL) {
        let fm = FileManager.default
        guard let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            statusMessage = ""
            updateAvailable = false
            return
        }
        let targetApp = downloads.appendingPathComponent("OpenDiskTest (new).app")
        do {
            if fm.fileExists(atPath: targetApp.path) {
                try fm.removeItem(at: targetApp)
            }
            try fm.moveItem(at: newApp, to: targetApp)
            try? fm.removeItem(at: extractDir)
            stripQuarantine(targetApp)
            log("Ready-to-use app placed in Downloads: \(targetApp.lastPathComponent)")
            NSWorkspace.shared.activateFileViewerSelecting([targetApp])
        } catch {
            log("Manual install fallback failed: \(error.localizedDescription)")
            NSWorkspace.shared.activateFileViewerSelecting([newApp])
        }
        statusMessage = ""
        updateAvailable = false
    }

    private func stripQuarantine(_ url: URL) {
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? xattr.run()
        xattr.waitUntilExit()
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
