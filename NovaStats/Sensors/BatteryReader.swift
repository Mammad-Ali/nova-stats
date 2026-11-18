import Foundation
import IOKit

struct BatterySample {
    var present = false
    var percent = 0.0
    var charging = false
    var pluggedIn = false
    var full = false
    var health: Double?
    var cycles = 0
    var minutesLeft: Int?
    var batteryWatts = 0.0 // plus while charging, minus while running on it
    var fullCapacity = 0
    var designCapacity = 0
    var adapter: String?
    var adapterWatts: Double?
    var systemWatts: Double? // the whole mac
    var chargerWatts: Double? // what the charger delivers right now
}

final class BatteryReader {
    // runs on the sampler queue, same as the other smc reads
    func read() -> BatterySample {
        var s = BatterySample()
        var value = 0.0
        if smc_read("PSTR", &value) == 0, value > 0 { s.systemWatts = value }
        if smc_read("PDTR", &value) == 0, value > 0.5 { s.chargerWatts = value }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return s }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return s }

        s.present = true
        let current = d["CurrentCapacity"] as? Int ?? 0
        let max = d["MaxCapacity"] as? Int ?? 100
        s.percent = max > 0 ? Double(current) / Double(max) : 0
        s.charging = d["IsCharging"] as? Bool ?? false
        s.pluggedIn = d["ExternalConnected"] as? Bool ?? false
        s.full = d["FullyCharged"] as? Bool ?? false
        s.cycles = d["CycleCount"] as? Int ?? 0

        // apple silicon keeps the real mAh numbers in BatteryData
        let data = d["BatteryData"] as? [String: Any] ?? [:]
        s.designCapacity = (data["DesignCapacity"] ?? d["DesignCapacity"]) as? Int ?? 0
        s.fullCapacity = (data["FullChargeCapacity"] ?? d["AppleRawMaxCapacity"]) as? Int ?? 0
        let nominal = (data["NominalChargeCapacity"] ?? d["NominalChargeCapacity"]) as? Int ?? s.fullCapacity
        if s.designCapacity > 0, nominal > 0 {
            s.health = min(Double(nominal) / Double(s.designCapacity), 1)
        }

        // 65535 means macOS is still working it out
        let minutes = (s.charging ? d["AvgTimeToFull"] : d["AvgTimeToEmpty"]) as? Int
        if let minutes, minutes > 0, minutes < 65535 { s.minutesLeft = minutes }

        let volts = Double(d["Voltage"] as? Int ?? 0) / 1000
        let amps = Double((d["Amperage"] as? NSNumber)?.int64Value ?? 0) / 1000
        s.batteryWatts = volts * amps

        if s.pluggedIn, let adapter = d["AdapterDetails"] as? [String: Any] {
            s.adapter = adapter["Name"] as? String ?? adapter["Description"] as? String
            if let watts = adapter["Watts"] as? Int, watts > 0 { s.adapterWatts = Double(watts) }
        }
        return s
    }
}
