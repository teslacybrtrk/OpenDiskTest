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

/// One CPU reading: aggregate busy fraction plus per-core busy fractions (0...1).
struct CPUReading {
    let aggregate: Double
    let perCore: [Double]
}

/// Stateful CPU sampler: diffs `host_processor_info` tick counters between calls.
/// Keeps per-core previous ticks so it can report both aggregate and per-core load.
final class CPUUsageSampler {
    /// Previous per-core ticks: [core][user, system, idle, nice].
    private var previous: [[UInt32]]?

    /// Aggregate-only convenience (0...1), or nil on the first call.
    func sample() -> Double? { reading()?.aggregate }

    /// Full reading (aggregate + per-core), or nil on the first call.
    func reading() -> CPUReading? {
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

        let cores = Int(cpuCount)
        var current: [[UInt32]] = []
        current.reserveCapacity(cores)
        for core in 0..<cores {
            let base = core * Int(CPU_STATE_MAX)
            current.append([
                UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ])
        }

        defer { previous = current }
        guard let prev = previous, prev.count == current.count else { return nil }

        var perCore: [Double] = []
        perCore.reserveCapacity(cores)
        var busyTotal = 0.0, grandTotal = 0.0
        for core in 0..<cores {
            let userD   = Double(current[core][0] &- prev[core][0])
            let systemD = Double(current[core][1] &- prev[core][1])
            let idleD   = Double(current[core][2] &- prev[core][2])
            let niceD   = Double(current[core][3] &- prev[core][3])
            let busy = userD + systemD + niceD
            let total = busy + idleD
            perCore.append(total > 0 ? max(0, min(1, busy / total)) : 0)
            busyTotal += busy
            grandTotal += total
        }
        let aggregate = grandTotal > 0 ? max(0, min(1, busyTotal / grandTotal)) : 0
        return CPUReading(aggregate: aggregate, perCore: perCore)
    }
}

enum SwapStats {
    /// Returns (used, total) swap bytes via `vm.swapusage`. Zeros if unavailable.
    static func usage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
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

    struct Breakdown {
        var active: UInt64 = 0
        var wired: UInt64 = 0
        var compressed: UInt64 = 0
        var free: UInt64 = 0
        var total: UInt64 = 0
        var used: UInt64 { active + wired + compressed }
    }

    /// Full memory breakdown for the System Monitor.
    static func breakdown() -> Breakdown {
        var b = Breakdown(total: totalBytes)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return b }
        let pageSize = UInt64(vm_kernel_page_size)
        b.active     = UInt64(stats.active_count) * pageSize
        b.wired      = UInt64(stats.wire_count) * pageSize
        b.compressed = UInt64(stats.compressor_page_count) * pageSize
        b.free       = (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * pageSize
        return b
    }
}
