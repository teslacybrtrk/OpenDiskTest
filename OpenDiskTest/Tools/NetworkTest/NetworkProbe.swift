import Foundation

// MARK: - NetworkProbe
//
// Low-level throughput measurement against Cloudflare's open speed endpoints.
// A URLSession delegate accumulates streamed download bytes and sent upload
// bytes into thread-safe counters; the view model samples them on a timer to
// derive live Mbps. Parallel workers are used to saturate fast links (a single
// TCP stream under-measures).

final class NetworkProbe: NSObject, URLSessionDataDelegate {
    static let downloadURL = "https://speed.cloudflare.com/__down?bytes="
    static let uploadURL   = "https://speed.cloudflare.com/__up"

    private let lock = NSLock()
    private var _downBytes: Int64 = 0
    private var _upBytes: Int64 = 0

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.timeoutIntervalForRequest = 30
        cfg.httpMaximumConnectionsPerHost = 16
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private var tasks: [URLSessionTask] = []

    // MARK: Counters

    var downBytes: Int64 { lock.lock(); defer { lock.unlock() }; return _downBytes }
    var upBytes: Int64 { lock.lock(); defer { lock.unlock() }; return _upBytes }

    func resetCounters() {
        lock.lock(); _downBytes = 0; _upBytes = 0; lock.unlock()
    }

    // MARK: Latency

    /// Median round-trip (ms) and jitter (stdev, ms) over several tiny requests.
    /// Also returns the Cloudflare colo if reported. Returns nil on failure.
    func measureLatency(samples: Int = 8) async -> (median: Double, jitter: Double, colo: String?)? {
        var times: [Double] = []
        var colo: String?
        guard let url = URL(string: Self.downloadURL + "0") else { return nil }
        for i in 0..<samples {
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let start = DispatchTime.now()
            do {
                let (_, response) = try await session.data(for: req)
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                if i > 0 { times.append(elapsed) } // drop first (TLS/DNS warmup)
                if colo == nil, let http = response as? HTTPURLResponse,
                   let meta = http.value(forHTTPHeaderField: "cf-meta-colo") {
                    colo = meta
                }
            } catch {
                continue
            }
        }
        guard !times.isEmpty else { return nil }
        let sorted = times.sorted()
        let median = sorted[sorted.count / 2]
        let mean = times.reduce(0, +) / Double(times.count)
        let variance = times.reduce(0) { $0 + pow($1 - mean, 2) } / Double(times.count)
        return (median, sqrt(variance), colo)
    }

    // MARK: Download / Upload workers

    /// Starts `workers` streaming download tasks, each pulling a large payload.
    func startDownload(workers: Int, bytesPerRequest: Int = 200_000_000) {
        guard let url = URL(string: Self.downloadURL + "\(bytesPerRequest)") else { return }
        for _ in 0..<workers {
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let task = session.dataTask(with: req)
            tasks.append(task)
            task.resume()
        }
    }

    /// Starts `workers` upload tasks streaming random data.
    func startUpload(workers: Int, payloadBytes: Int = 100_000_000) {
        guard let url = URL(string: Self.uploadURL) else { return }
        let payload = Self.randomData(payloadBytes)
        for _ in 0..<workers {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let task = session.uploadTask(with: req, from: payload)
            tasks.append(task)
            task.resume()
        }
    }

    func stopAll() {
        for task in tasks { task.cancel() }
        tasks.removeAll()
    }

    // MARK: URLSessionDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); _downBytes += Int64(data.count); lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        lock.lock(); _upBytes += bytesSent; lock.unlock()
    }

    // MARK: Helpers

    private static func randomData(_ count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            // Fill with a cheap pseudo-random pattern (incompressible enough for upload).
            var seed: UInt64 = 0x9E3779B97F4A7C15
            let words = raw.count / 8
            let p = base.assumingMemoryBound(to: UInt64.self)
            for i in 0..<words {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                p[i] = seed
            }
        }
        return data
    }
}
