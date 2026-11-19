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
    // both run on the sampler queue, same as the other smc reads
    func readPower(into s: inout BatterySample) {
        var value = 0.0
        s.systemWatts = smc_read("PSTR", &value) == 0 && value > 0 ? value : nil
        s.chargerWatts = smc_read("PDTR", &value) == 0 && value > 0.5 ? value : nil
    }

    // the battery's registry entry is big, so this one runs less often
    func readBattery(into s: inout BatterySample) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            s.present = false
            return
        }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return }

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
        s.health = s.designCapacity > 0 && nominal > 0 ? min(Double(nominal) / Double(s.designCapacity), 1) : nil

        // 65535 means macOS is still working it out
        let minutes = (s.charging ? d["AvgTimeToFull"] : d["AvgTimeToEmpty"]) as? Int
        s.minutesLeft = minutes.flatMap { $0 > 0 && $0 < 65535 ? $0 : nil }

        let volts = Double(d["Voltage"] as? Int ?? 0) / 1000
        let amps = Double((d["Amperage"] as? NSNumber)?.int64Value ?? 0) / 1000
        s.batteryWatts = volts * amps

        s.adapter = nil
        s.adapterWatts = nil
        if s.pluggedIn, let adapter = d["AdapterDetails"] as? [String: Any] {
            s.adapter = adapter["Name"] as? String ?? adapter["Description"] as? String
            if let watts = adapter["Watts"] as? Int, watts > 0 { s.adapterWatts = Double(watts) }
        }
    }
}
