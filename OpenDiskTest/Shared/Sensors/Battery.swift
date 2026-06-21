import Foundation
import IOKit
import IOKit.ps

// MARK: - Battery
//
// Reads battery state via the public IOKit power-sources API (charge, charging
// state, time remaining) and AppleSmartBattery registry properties (cycle count,
// condition, design/current capacity for a health %). All public, no privileges.
// `nil` / `isPresent == false` on desktops without a battery.

struct BatteryInfo {
    var isPresent: Bool = false
    var charge: Double = 0            // 0...1
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var timeToEmptyMinutes: Int?      // discharging
    var timeToFullMinutes: Int?       // charging
    var cycleCount: Int?
    var condition: String?            // "Normal", "Service Recommended", etc.
    var healthPercent: Int?           // current max capacity / design capacity
}

enum Battery {
    static func read() -> BatteryInfo {
        var info = BatteryInfo()

        // --- Power sources (charge %, charging, time estimates) ---
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
                guard (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

                info.isPresent = true
                if let cur = desc[kIOPSCurrentCapacityKey] as? Int,
                   let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                    info.charge = Double(cur) / Double(max)
                }
                if let state = desc[kIOPSPowerSourceStateKey] as? String {
                    info.isPluggedIn = (state == kIOPSACPowerValue)
                }
                info.isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
                if let t = desc[kIOPSTimeToEmptyKey] as? Int, t > 0 { info.timeToEmptyMinutes = t }
                if let t = desc[kIOPSTimeToFullChargeKey] as? Int, t > 0 { info.timeToFullMinutes = t }
            }
        }

        // --- AppleSmartBattery registry (cycles, condition, health) ---
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            info.isPresent = true
            if let cycles = registryInt(service, "CycleCount") { info.cycleCount = cycles }
            if let cond = registryString(service, "BatteryHealthCondition") {
                info.condition = cond.isEmpty ? "Normal" : cond
            } else {
                info.condition = "Normal"
            }
            // Health % = current max capacity / design capacity.
            if let design = registryInt(service, "DesignCapacity"), design > 0,
               let maxCap = registryInt(service, "AppleRawMaxCapacity") ?? registryInt(service, "MaxCapacity") {
                info.healthPercent = Int((Double(maxCap) / Double(design) * 100).rounded())
            }
        }

        return info
    }

    private static func registryInt(_ service: io_service_t, _ key: String) -> Int? {
        guard let prop = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        return (prop as? NSNumber)?.intValue
    }

    private static func registryString(_ service: io_service_t, _ key: String) -> String? {
        guard let prop = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        return prop as? String
    }
}
