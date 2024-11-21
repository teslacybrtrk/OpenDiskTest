import Foundation
import Combine

class DiskSpeedTestViewModel: ObservableObject {
    @Published var fileSize: Double = 10 // Default 10 MB
    @Published var iterations: Int = 100 // Default 100 iterations
    @Published var isRunning = false
    @Published var results: [TestResult] = [
        TestResult(name: "Sequential Write"),
        TestResult(name: "Sequential Read"),
        TestResult(name: "Random Write"),
        TestResult(name: "Random Read")
    ]
    @Published var logs: [String] = []
    
    private let fileManager = FileManager.default
    private var cancellables = Set<AnyCancellable>()
    
    func runTests() {
        isRunning = true
        results = results.map { TestResult(name: $0.name) }
        logs.removeAll()
        
        addLog("Starting tests with file size: \(String(format: "%.2f", fileSize)) MB and \(iterations) iterations")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let testFileURL = self.getTestFileURL()
            let fileSizeBytes = Int(self.fileSize * 1024 * 1024)
            
            self.addLog("Test file location: \(testFileURL.path)")
            
            // Ensure the file exists before testing
            if !self.fileManager.fileExists(atPath: testFileURL.path) {
                do {
                    try "".write(to: testFileURL, atomically: true, encoding: .utf8)
                    self.addLog("Created test file at: \(testFileURL.path)")
                } catch {
                    self.addLog("Error creating test file: \(error)")
                    DispatchQueue.main.async {
                        self.isRunning = false
                    }
                    return
                }
            }
            
            for iteration in 1...self.iterations {
                guard self.isRunning else { break }
                
                self.addLog("Starting iteration \(iteration)")
                
                self.updateTest(index: 0, name: "Sequential Write") { self.sequentialWrite(size: fileSizeBytes, to: testFileURL) }
                self.updateTest(index: 1, name: "Sequential Read") { self.sequentialRead(from: testFileURL) }
                self.updateTest(index: 2, name: "Random Write") { self.randomWrite(size: fileSizeBytes, to: testFileURL) }
                self.updateTest(index: 3, name: "Random Read") { self.randomRead(from: testFileURL) }
                
                self.addLog("Completed iteration \(iteration)")
            }
            
            DispatchQueue.main.async {
                self.isRunning = false
                self.addLog("All tests completed")
            }
            
            try? self.fileManager.removeItem(at: testFileURL)
            self.addLog("Removed test file from: \(testFileURL.path)")
        }
    }
    
    func stopTests() {
        isRunning = false
        addLog("Tests stopped by user")
    }
    
    private func updateTest(index: Int, name: String, operation: () -> Double) {
        let speed = operation()
        DispatchQueue.main.async {
            self.results[index].speeds.append(speed)
            self.results[index].sortedSpeeds = self.results[index].speeds.enumerated().sorted { $0.element < $1.element }
            
            self.addLog("\(name) - Speed: \(String(format: "%.2f", speed)) MB/s, Min: \(String(format: "%.2f", self.results[index].minSpeed)) MB/s, Avg: \(String(format: "%.2f", self.results[index].avgSpeed)) MB/s, Max: \(String(format: "%.2f", self.results[index].maxSpeed)) MB/s")
        }
    }
    
    private func addLog(_ message: String) {
        DispatchQueue.main.async {
            self.logs.append("[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(message)")
        }
    }
    
    private func getTestFileURL() -> URL {
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return tempDirectoryURL.appendingPathComponent("diskspeedtest.tmp")
    }
    
    // Disk operation methods
    private func sequentialWrite(size: Int, to url: URL) -> Double {
        let data = Data(count: size)
        let start = Date()
        
        do {
            try data.write(to: url)
        } catch {
            addLog("Error in sequential write: \(error)")
            return 0
        }
        
        let end = Date()
        let timeInterval = end.timeIntervalSince(start)
        return Double(size) / timeInterval / (1024 * 1024) // MB/s
    }
    
    private func sequentialRead(from url: URL) -> Double {
        let start = Date()
        
        do {
            _ = try Data(contentsOf: url)
        } catch {
            addLog("Error in sequential read: \(error)")
            return 0
        }
        
        let end = Date()
        let timeInterval = end.timeIntervalSince(start)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Double(fileSize) / timeInterval / (1024 * 1024) // MB/s
    }
    
    private func randomWrite(size: Int, to url: URL) -> Double {
        let chunkSize = 4096 // 4 KB chunks
        let chunks = size / chunkSize
        let data = Data(count: chunkSize)
        let start = Date()
        
        do {
            let fileHandle = try FileHandle(forWritingTo: url)
            defer { fileHandle.closeFile() }
            
            for _ in 0..<chunks {
                let offset = UInt64(arc4random_uniform(UInt32(size)))
                fileHandle.seek(toFileOffset: offset)
                fileHandle.write(data)
            }
        } catch {
            addLog("Error in random write: \(error)")
            return 0
        }
        
        let end = Date()
        let timeInterval = end.timeIntervalSince(start)
        return Double(size) / timeInterval / (1024 * 1024) // MB/s
    }
    
    private func randomRead(from url: URL) -> Double {
        let chunkSize = 4096 // 4 KB chunks
        let start = Date()
        
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { fileHandle.closeFile() }
            
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let chunks = fileSize / chunkSize
            
            for _ in 0..<chunks {
                let offset = UInt64(arc4random_uniform(UInt32(fileSize)))
                fileHandle.seek(toFileOffset: offset)
                _ = fileHandle.readData(ofLength: chunkSize)
            }
        } catch {
            addLog("Error in random read: \(error)")
            return 0
        }
        
        let end = Date()
        let timeInterval = end.timeIntervalSince(start)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Double(fileSize) / timeInterval / (1024 * 1024) // MB/s
    }
}

struct TestResult: Identifiable {
    let id = UUID()
    let name: String
    var speeds: [Double] = []
    var sortedSpeeds: [(offset: Int, element: Double)] = []
    
    var minSpeed: Double { speeds.min() ?? 0 }
    var avgSpeed: Double { speeds.isEmpty ? 0 : speeds.reduce(0, +) / Double(speeds.count) }
    var maxSpeed: Double { speeds.max() ?? 0 }
}
