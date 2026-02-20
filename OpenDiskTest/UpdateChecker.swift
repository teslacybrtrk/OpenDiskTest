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
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/tags/latest")!
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

    func performUpdate() {
        guard let assetURL = assetURL else { return }
        isDownloading = true
        downloadProgress = 0

        let delegate = DownloadDelegate { [weak self] progress in
            DispatchQueue.main.async { self?.downloadProgress = progress }
        } completion: { [weak self] tempFileURL, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let tempFileURL = tempFileURL {
                    self.installUpdate(from: tempFileURL)
                } else {
                    self.isDownloading = false
                }
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        session.downloadTask(with: assetURL).resume()
    }

    private func installUpdate(from zipFile: URL) {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("OpenDiskTest-update-\(UUID().uuidString)")

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            isDownloading = false
            return
        }

        // Extract using ditto
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipFile.path, tempDir.path]

        do {
            try ditto.run()
            ditto.waitUntilExit()
        } catch {
            isDownloading = false
            return
        }

        guard ditto.terminationStatus == 0 else {
            isDownloading = false
            return
        }

        // Find the .app bundle in extracted contents
        guard let contents = try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil),
              let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
            isDownloading = false
            return
        }

        let currentAppPath = Bundle.main.bundlePath
        let newAppPath = newApp.path

        // Launch a shell script that waits for us to quit, then swaps the app and relaunches
        let script = """
        #!/bin/bash
        APP_PID=\(ProcessInfo.processInfo.processIdentifier)
        while kill -0 $APP_PID 2>/dev/null; do sleep 0.2; done
        rm -rf "\(currentAppPath)"
        mv "\(newAppPath)" "\(currentAppPath)"
        rm -rf "\(tempDir.path)"
        open "\(currentAppPath)"
        """

        let scriptFile = tempDir.appendingPathComponent("update.sh")
        try? script.write(to: scriptFile, atomically: true, encoding: .utf8)

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [scriptFile.path]
        try? launcher.run()

        NSApplication.shared.terminate(nil)
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
        // Move to a stable temp location since the original will be deleted
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
