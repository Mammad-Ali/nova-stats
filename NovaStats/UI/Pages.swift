import SwiftUI

struct ChartCard: View {
    var title = "History"
    var series: [Series]
    var legend: [(Color, String)]
    var maxValue: Double? = nil
    var format: (Double) -> String
    @State private var range = 300

    var body: some View {
        let points = min(range, 300)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Nova.textHi)
                ForEach(legend.indices, id: \.self) { i in
                    Legend(color: legend[i].0, label: legend[i].1)
                }
                Spacer()
                PillPicker(options: [300, 1800, 3600], label: { $0 == 300 ? "5 min" : $0 == 1800 ? "30 min" : "1 hour" },
                           selection: $range, small: true)
            }
            LineChart(series: series.map { Series(color: $0.color, values: downsample($0.values, seconds: range, points: points)) },
                      window: points, maxValue: maxValue, grid: format)
        }
        .card()
    }
}

struct BigGauge: View {
    var value: Double
    var caption: String

    var body: some View {
        Ring(value: value, width: 11) {
            VStack(spacing: 2) {
                Text(formatPercent(value))
                    .font(.system(size: 40, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Nova.textHi)
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Nova.textLo)
            }
        }
        .frame(width: 170, height: 170)
        .card(.center)
        .frame(width: 230)
    }
}

struct StatGrid: View {
    var stats: [(String, String, Color)]
    var columns = 3

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns), alignment: .leading, spacing: 18) {
            ForEach(stats.indices, id: \.self) { i in
                Stat(label: stats[i].0, value: stats[i].1, color: stats[i].2)
            }
        }
        .card(.leading)
    }
}

struct CPUPage: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        let r = m.cpuReader
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                BigGauge(value: m.cpu.total, caption: "load")
                StatGrid(stats: [
                    ("User", formatPercent(m.cpu.user), Nova.textHi),
                    ("System", formatPercent(m.cpu.system), Nova.textHi),
                    ("Idle", formatPercent(1 - m.cpu.total), Nova.textHi),
                    ("Temperature", formatTemp(m.temps.cpu), Nova.heat(m.temps.cpu)),
                    ("Hottest core", formatTemp(m.temps.cpuHottest), Nova.heat(m.temps.cpuHottest)),
                    ("Cores", "\(r.superCores) \(r.superName) · \(r.efficiencyCores) \(r.efficiencyName)", Nova.textHi),
                ])
            }
            .frame(height: 230)
            HStack(spacing: 16) {
                ChartCard(series: [Series(color: Nova.sun, values: m.history.cpu)],
                          legend: [(Nova.sun, "Load")], maxValue: 1, format: formatPercent)
                CoresCard()
                    .frame(width: 360)
            }
        }
    }
}

struct CoresCard: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        let r = m.cpuReader
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "square.grid.3x3", title: "Cores")
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(m.cpu.cores.indices, id: \.self) { i in
                        let v = m.cpu.cores[i]
                        // efficiency cores come first in the kernel's list
                        let label = i < r.efficiencyCores
                            ? "\(r.efficiencyName.prefix(1))\(i + 1)"
                            : "\(r.superName.prefix(1))\(i - r.efficiencyCores + 1)"
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.06))
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Nova.sun.opacity(i < r.efficiencyCores ? 0.65 : 1))
                                    .frame(height: max((geo.size.height - 22) * v, 3))
                            }
                            Text(label)
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Nova.textLo)
                                .frame(height: 16)
                        }
                    }
                }
            }
        }
        .card()
    }
}

struct GPUPage: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                BigGauge(value: m.gpu.usage, caption: "usage")
                StatGrid(stats: [
                    ("Model", m.gpuReader.model, Nova.textHi),
                    ("Cores", "\(m.gpuReader.cores)", Nova.textHi),
                    ("Memory in use", formatMemory(m.gpu.memory), Nova.textHi),
                    ("Temperature", formatTemp(m.temps.gpu), Nova.heat(m.temps.gpu)),
                ], columns: 2)
            }
            .frame(height: 230)
            ChartCard(series: [Series(color: Nova.sun, values: m.history.gpu)],
                      legend: [(Nova.sun, "Usage")], maxValue: 1, format: formatPercent)
        }
    }
}

struct MemoryPage: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        let mem = m.memory
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                BigGauge(value: mem.fraction, caption: "used")
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formatMemory(mem.used))
                            .font(.system(size: 24, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Nova.textHi)
                        Text("used of \(formatMemory(mem.total))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Nova.textMid)
                        Spacer()
                        PressureChip(level: mem.pressure)
                    }
                    SplitBar(total: mem.total, parts: [
                        (mem.app, Nova.down), (mem.wired, Nova.up), (mem.compressed, Nova.alt),
                    ])
                    HStack(spacing: 0) {
                        Stat(label: "App", value: formatMemory(mem.app), color: Nova.down).frame(maxWidth: .infinity, alignment: .leading)
                        Stat(label: "Wired", value: formatMemory(mem.wired), color: Nova.up).frame(maxWidth: .infinity, alignment: .leading)
                        Stat(label: "Compressed", value: formatMemory(mem.compressed), color: Nova.alt).frame(maxWidth: .infinity, alignment: .leading)
                        Stat(label: "Cached", value: formatMemory(mem.cached)).frame(maxWidth: .infinity, alignment: .leading)
                        Stat(label: "Swap", value: formatMemory(mem.swap)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .card(.leading)
            }
            .frame(height: 230)
            HStack(spacing: 16) {
                ChartCard(series: [Series(color: Nova.sun, values: m.history.memory)],
                          legend: [(Nova.sun, "Used")], maxValue: 1, format: formatPercent)
                AppsCard()
                    .frame(width: 380)
            }
        }
    }
}

struct SplitBar: View {
    var total: Double
    var parts: [(Double, Color)]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(parts.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(parts[i].1)
                        .frame(width: max(geo.size.width * parts[i].0 / max(total, 1) - 2, 0))
                }
                Spacer(minLength: 0)
            }
            .background(Capsule().fill(.white.opacity(0.08)))
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }
}

struct DiskPage: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        let d = m.disk
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                BigGauge(value: d.fraction, caption: "full")
                StatGrid(stats: [
                    ("Volume", d.name, Nova.textHi),
                    ("Free", formatBytes(d.free), Nova.textHi),
                    ("Used", formatBytes(d.used), Nova.textHi),
                    ("Capacity", formatBytes(d.total), Nova.textHi),
                    ("Read", formatRate(d.read), Nova.down),
                    ("Write", formatRate(d.write), Nova.up),
                    ("SSD temperature", formatTemp(m.temps.ssd), Nova.heat(m.temps.ssd)),
                ], columns: 4)
            }
            .frame(height: 230)
            HStack(spacing: 16) {
                ChartCard(series: [Series(color: Nova.down, values: m.history.read), Series(color: Nova.up, values: m.history.write)],
                          legend: [(Nova.down, "Read"), (Nova.up, "Write")], format: formatRate)
                DrivesCard()
                    .frame(width: 380)
            }
        }
    }
}

struct NetworkPage: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        let n = m.net
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                HStack {
                    RateView(icon: "arrow.down", color: Nova.down, label: "Download", value: formatRate(n.down), size: 30)
                    RateView(icon: "arrow.up", color: Nova.up, label: "Upload", value: formatRate(n.up), size: 30)
                }
                .card(.leading)
                StatGrid(stats: [
                    ("Connection", n.ip.isEmpty ? "Offline" : n.kind, Nova.textHi),
                    ("Interface", n.interface.isEmpty ? "—" : n.interface, Nova.textHi),
                    ("Local IP", n.ip.isEmpty ? "—" : n.ip, Nova.textHi),
                    ("Received since boot", formatBytes(n.totalDown), Nova.down),
                    ("Sent since boot", formatBytes(n.totalUp), Nova.up),
                ], columns: 3)
            }
            .frame(height: 230)
            ChartCard(series: [Series(color: Nova.down, values: m.history.down), Series(color: Nova.up, values: m.history.up)],
                      legend: [(Nova.down, "Download"), (Nova.up, "Upload")], format: formatRate)
        }
    }
}

struct SensorsPage: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        let t = m.temps
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                StatGrid(stats: [
                    ("CPU", formatTemp(t.cpu), Nova.heat(t.cpu)),
                    ("CPU hottest", formatTemp(t.cpuHottest), Nova.heat(t.cpuHottest)),
                    ("GPU", formatTemp(t.gpu), Nova.heat(t.gpu)),
                    ("SSD", formatTemp(t.ssd), Nova.heat(t.ssd)),
                    ("Battery", formatTemp(t.battery), Nova.heat(t.battery)),
                    ("Fans", t.hasFans ? t.fans.map { "\(Int($0)) rpm" }.joined(separator: " · ") : "Fanless", Nova.textHi),
                ], columns: 3)
                ChartCard(title: "CPU and GPU", series: [Series(color: Nova.sun, values: m.history.cpuTemp), Series(color: Nova.up, values: m.history.gpuTemp)],
                          legend: [(Nova.sun, "CPU"), (Nova.up, "GPU")], maxValue: 110, format: { formatTemp($0) })
            }
            .frame(height: 230)
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(icon: "sensor", title: "All sensors") {
                    Chip(text: "\(t.sensors.count)")
                }
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 4), spacing: 10) {
                        ForEach(t.sensors.indices, id: \.self) { i in
                            HStack {
                                Text(t.sensors[i].name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Nova.textMid)
                                    .lineLimit(1)
                                Spacer()
                                Text(formatTemp(t.sensors[i].value))
                                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Nova.heat(t.sensors[i].value))
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .card()
        }
    }
}

struct DrivesCard: View {
    @Environment(Monitor.self) private var m
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "externaldrive", title: "Drives") {
                Chip(text: "\(m.disk.volumes.count)")
            }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(m.disk.volumes) { volume in
                        HStack(spacing: 10) {
                            Image(nsImage: AppIcons.icon(volume.path))
                                .resizable()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(volume.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Nova.textHi)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text("\(formatBytes(volume.free)) free")
                                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(Nova.textMid)
                                }
                                Meter(value: volume.fraction, height: 3)
                            }
                            if volume.ejectable {
                                Button {
                                    eject(volume)
                                } label: {
                                    Image(systemName: "eject.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Nova.textMid)
                                        .frame(width: 26, height: 26)
                                        .background(Circle().fill(.white.opacity(0.08)))
                                }
                                .buttonStyle(.plain)
                                .help("Eject \(volume.name)")
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            if let problem {
                Text(problem)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Nova.amber)
            }
        }
        .card()
    }

    private func eject(_ volume: Volume) {
        problem = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: volume.path))
            } catch {
                DispatchQueue.main.async { problem = "Couldn't eject \(volume.name). An app may still be using it." }
            }
        }
    }
}

struct BatteryPage: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        let b = m.battery
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                if b.present {
                    BigGauge(value: b.percent, caption: status(b))
                } else {
                    VStack(spacing: 6) {
                        Text(b.systemWatts.map(formatWatts) ?? "—")
                            .font(.system(size: 36, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Nova.textHi)
                        Text("whole Mac")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Nova.textLo)
                    }
                    .card(.center)
                    .frame(width: 230)
                }
                StatGrid(stats: stats(b), columns: 3)
            }
            .frame(height: 230)
            ChartCard(title: "Power", series: [Series(color: Nova.sun, values: m.history.power)],
                      legend: [(Nova.sun, "Whole Mac")], format: formatWatts)
        }
    }

    private func status(_ b: BatterySample) -> String {
        if b.full { return "charged" }
        if b.charging { return "charging" }
        return b.pluggedIn ? "plugged in" : "on battery"
    }

    private func stats(_ b: BatterySample) -> [(String, String, Color)] {
        var list: [(String, String, Color)] = [
            ("Whole Mac uses", b.systemWatts.map(formatWatts) ?? "—", Nova.textHi),
        ]
        guard b.present else {
            list.append(("Battery", "This Mac has none", Nova.textMid))
            return list
        }
        let healthColor = (b.health ?? 1) >= 0.8 ? Nova.green : (b.health ?? 1) >= 0.6 ? Nova.amber : Nova.red
        let flow = b.batteryWatts > 0.05 ? "+" + formatWatts(b.batteryWatts) : formatWatts(b.batteryWatts)
        list += [
            (b.charging ? "Into the battery" : "From the battery", flow, b.batteryWatts > 0.05 ? Nova.green : Nova.textHi),
            (b.charging ? "Full in" : "Time left", b.full ? "Charged" : b.minutesLeft.map(formatMinutes) ?? "Working it out", Nova.textHi),
            ("Health", b.health.map(formatPercent) ?? "—", healthColor),
            ("Charge cycles", "\(b.cycles)", Nova.textHi),
            ("Capacity", b.fullCapacity > 0 ? "\(b.fullCapacity) of \(b.designCapacity) mAh" : "—", Nova.textHi),
            ("Charger", b.pluggedIn ? (b.adapter ?? "Plugged in") : "Not plugged in", Nova.textHi),
            ("Charger gives", b.chargerWatts.map(formatWatts) ?? "—", Nova.textHi),
            ("Temperature", formatTemp(m.temps.battery), Nova.heat(m.temps.battery)),
        ]
        return list
    }
}
