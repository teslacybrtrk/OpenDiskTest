import SwiftUI

// MARK: - NetworkTestViewModel
//
// Orchestrates a three-phase speed test (latency → download → upload) against
// Cloudflare, sampling the probe's byte counters ~4×/sec to drive a live readout
// and graph. Each throughput phase discards a short warmup, then averages the
// steady-state samples.

@MainActor
final class NetworkTestViewModel: ObservableObject {
    enum Phase: String {
        case idle, latency, download, upload, finished
        var title: String {
            switch self {
            case .idle: return "Ready"
            case .latency: return "Measuring latency…"
            case .download: return "Testing download…"
            case .upload: return "Testing upload…"
            case .finished: return "Done"
            }
        }
    }

    struct Sample: Identifiable {
        let id = UUID()
        let t: Double          // seconds since phase start
        let mbps: Double
        let isUpload: Bool
    }

    @Published var phase: Phase = .idle
    @Published var isRunning = false
    @Published var liveMbps: Double = 0
    @Published var phaseProgress: Double = 0

    @Published var downloadMbps: Double?
    @Published var uploadMbps: Double?
    @Published var latencyMs: Double?
    @Published var jitterMs: Double?
    @Published var colo: String?

    @Published var downloadSamples: [Sample] = []
    @Published var uploadSamples: [Sample] = []

    private var probe: NetworkProbe?
    private var task: Task<Void, Never>?

    private let workers = 4
    private let phaseDuration: Double = 9.0
    private let warmup: Double = 1.5
    private let sampleInterval: Double = 0.25

    var peakMbps: Double {
        (downloadSamples + uploadSamples).map(\.mbps).max() ?? 1
    }

    func start() {
        guard !isRunning else { return }
        reset()
        isRunning = true
        let probe = NetworkProbe()
        self.probe = probe

        task = Task { [weak self] in
            guard let self else { return }
            await self.runLatency(probe)
            if Task.isCancelled { return }
            await self.runThroughput(probe, upload: false)
            if Task.isCancelled { return }
            await self.runThroughput(probe, upload: true)
            if Task.isCancelled { return }
            await MainActor.run {
                self.phase = .finished
                self.liveMbps = 0
                self.isRunning = false
            }
        }
    }

    func cancel() {
        task?.cancel()
        probe?.stopAll()
        isRunning = false
        phase = .idle
        liveMbps = 0
    }

    private func reset() {
        downloadMbps = nil; uploadMbps = nil
        latencyMs = nil; jitterMs = nil; colo = nil
        downloadSamples = []; uploadSamples = []
        liveMbps = 0; phaseProgress = 0
    }

    private func runLatency(_ probe: NetworkProbe) async {
        phase = .latency
        phaseProgress = 0
        if let result = await probe.measureLatency() {
            latencyMs = result.median
            jitterMs = result.jitter
            colo = result.colo
        }
        phaseProgress = 1
    }

    private func runThroughput(_ probe: NetworkProbe, upload: Bool) async {
        phase = upload ? .upload : .download
        phaseProgress = 0
        liveMbps = 0
        probe.resetCounters()
        if upload {
            probe.startUpload(workers: workers)
        } else {
            probe.startDownload(workers: workers)
        }

        let startTime = Date()
        var lastBytes: Int64 = 0
        var lastTime = startTime
        var steady: [Double] = []

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(sampleInterval * 1_000_000_000))
            let now = Date()
            let elapsed = now.timeIntervalSince(startTime)
            let dt = now.timeIntervalSince(lastTime)
            let total = upload ? probe.upBytes : probe.downBytes
            let delta = total - lastBytes
            lastBytes = total
            lastTime = now

            let mbps = dt > 0 ? Double(delta) * 8 / 1_000_000 / dt : 0
            liveMbps = mbps
            phaseProgress = min(1, elapsed / phaseDuration)

            let sample = Sample(t: elapsed, mbps: mbps, isUpload: upload)
            if upload { uploadSamples.append(sample) } else { downloadSamples.append(sample) }
            if elapsed > warmup { steady.append(mbps) }

            if elapsed >= phaseDuration { break }
        }

        probe.stopAll()
        let avg = steady.isEmpty ? liveMbps : steady.reduce(0, +) / Double(steady.count)
        if upload { uploadMbps = avg } else { downloadMbps = avg }
        liveMbps = 0
    }
}
