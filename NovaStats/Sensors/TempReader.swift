import Foundation

struct TempSample {
    var cpu: Double?
    var cpuHottest: Double?
    var gpu: Double?
    var ssd: Double?
    var battery: Double?
    var fans: [Double] = []
    var hasFans = false
    var sensors: [(name: String, value: Double)] = []
}

final class TempReader {
    private var cpuKeys: [String] = []
    private var gpuKeys: [String] = []
    private var fanCount = 0
    private var services: [(name: String, service: IOHIDServiceClient)] = []
    private var dies: [(name: String, value: Double)] = []
    private var diesRead: TimeInterval = -100
    private var client: IOHIDEventSystemClient? // services die with it, keep it around

    init() {
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        if let client {
            IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
            for case let service as IOHIDServiceClient in (IOHIDEventSystemClientCopyServices(client) as? [Any]) ?? [] {
                let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String ?? "Sensor"
                services.append((name, service))
            }
        }

        guard smc_open() == 0 else { return }
        var name = [CChar](repeating: 0, count: 5)
        var keys: [String] = []
        for i in 0..<smc_key_count() where smc_key_at(Int32(i), &name) == 0 {
            keys.append(cString(name))
        }
        #if arch(arm64)
        cpuKeys = keys.filter { $0.hasPrefix("Tp") || $0.hasPrefix("Te") }
        gpuKeys = keys.filter { $0.hasPrefix("Tg") }
        #else
        cpuKeys = keys.filter { ["TC0P", "TC0D", "TC0E", "TC0F"].contains($0) }
        gpuKeys = keys.filter { ["TG0P", "TG0D"].contains($0) }
        #endif
        if let n = smc("FNum") { fanCount = Int(n) }
    }

    func read() -> TempSample {
        var s = TempSample()

        let cpu = cpuKeys.compactMap { smc($0) }.filter(sane)
        let gpu = gpuKeys.compactMap { smc($0) }.filter(sane)
        s.cpu = average(cpu)
        s.cpuHottest = cpu.max()
        s.gpu = average(gpu)

        // asking hid for ~45 sensors every second is not free: the ssd and
        // one battery sensor each time, the soc dies every 5 seconds
        let now = ProcessInfo.processInfo.systemUptime
        let fullRead = now - diesRead >= 5 || cpuKeys.isEmpty
        var hid: [(name: String, value: Double)] = []
        var batterySeen = false
        for (name, service) in services {
            let isBattery = name.contains("battery")
            guard fullRead || name.hasPrefix("NAND") || (isBattery && !batterySeen) else { continue }
            if isBattery { batterySeen = true }
            guard let event = IOHIDServiceClientCopyEvent(service, 15, 0, 0) else { continue }
            let value = IOHIDEventGetFloatValue(event, 15 << 16)
            if sane(value) { hid.append((name, value)) }
        }
        if fullRead {
            dies = hid.filter { $0.name.hasPrefix("PMU") }
            diesRead = now
        }
        s.ssd = average(hid.filter { $0.name.hasPrefix("NAND") }.map(\.value))
        s.battery = average(hid.filter { $0.name.contains("battery") }.map(\.value))
        if s.cpu == nil {
            // no smc keys we know, fall back to the die sensors
            let die = dies.filter { $0.name.contains("tdie") }.map(\.value)
            s.cpu = average(die)
            s.cpuHottest = die.max()
        }

        s.hasFans = fanCount > 0
        s.fans = (0..<fanCount).compactMap { smc("F\($0)Ac") }
        s.sensors = cpu.enumerated().map { ("CPU \($0.offset + 1)", $0.element) }
            + gpu.enumerated().map { ("GPU \($0.offset + 1)", $0.element) }
        if let ssd = s.ssd { s.sensors.append(("SSD", ssd)) }
        if let battery = s.battery { s.sensors.append(("Battery", battery)) }
        s.sensors += dies.compactMap { item in pretty(item.name).map { ($0, item.value) } }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        return s
    }

    // turns "PMU2 tdie4" into "SoC 2 die 4", drops the ones shown above
    private func pretty(_ name: String) -> String? {
        let parts = name.split(separator: " ")
        guard parts.count == 2, parts[0].hasPrefix("PMU") else { return nil }
        let chip = parts[0] == "PMU" ? "SoC" : "SoC " + parts[0].dropFirst(3)
        if parts[1].hasPrefix("tdie") { return "\(chip) die \(parts[1].dropFirst(4))" }
        if parts[1].hasPrefix("tdev") { return "\(chip) sensor \(parts[1].dropFirst(4))" }
        return nil // tcal is a calibration constant, not a temperature
    }

    private func smc(_ key: String) -> Double? {
        var value = 0.0
        return smc_read(key, &value) == 0 ? value : nil
    }

    private func sane(_ v: Double) -> Bool { v > 1 && v < 130 }

    private func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
