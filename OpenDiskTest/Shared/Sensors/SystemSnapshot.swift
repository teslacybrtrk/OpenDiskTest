import Foundation
import Darwin

// MARK: - Cheap system metrics
//
// Low-overhead CPU and memory reads used by the dashboard heartbeat (and the
// full System Monitor in Phase 3). All public-API, no privileges required.
// CPU% is computed by diffing tick counters between two samples, so a
// `CPUUsageSampler` instance must persist across reads.

/// A point-in-time snapshot of cheap-to-read system metrics.
struct SystemSnapshot {
    /// Aggregate CPU busy fraction across all cores, 0...1. `nil` until two samples exist.
    var cpu: Double?
    /// Used memory fraction (active + wired + compressed) / total, 0...1.
    var memoryUsed: Double
    var memoryUsedBytes: UInt64
    var memoryTotalBytes: UInt64
}

/// Stateful CPU sampler: diffs `host_processor_info` tick counters between calls.
final class CPUUsageSampler {
    private var previousTicks: [UInt32]?

    /// Returns aggregate busy fraction (0...1), or nil on the very first call.
    func sample() -> Double? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(),
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount,
                                         &info,
                                         &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        // Sum user/system/nice/idle ticks across all cores.
        var totalUser: UInt32 = 0, totalSystem: UInt32 = 0
        var totalIdle: UInt32 = 0, totalNice: UInt32 = 0
        let cores = Int(cpuCount)
        for core in 0..<cores {
            let base = core * Int(CPU_STATE_MAX)
            totalUser   &+= UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            totalSystem &+= UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            totalIdle   &+= UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            totalNice   &+= UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
        }
        let current = [totalUser, totalSystem, totalIdle, totalNice]

        defer { previousTicks = current }
        guard let prev = previousTicks else { return nil }

        let userD   = Double(current[0] &- prev[0])
        let systemD = Double(current[1] &- prev[1])
        let idleD   = Double(current[2] &- prev[2])
        let niceD   = Double(current[3] &- prev[3])
        let busy = userD + systemD + niceD
        let total = busy + idleD
        guard total > 0 else { return nil }
        return max(0, min(1, busy / total))
    }
}

enum MemoryStats {
    /// Total physical RAM in bytes.
    static var totalBytes: UInt64 {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        return size
    }

    /// Returns (usedBytes, totalBytes). Used = (active + wired + compressed) * pageSize.
    static func usage() -> (used: UInt64, total: UInt64) {
        let total = totalBytes
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let pageSize = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        return (min(used, total), total)
    }
}
