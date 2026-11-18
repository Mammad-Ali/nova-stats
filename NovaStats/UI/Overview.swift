import SwiftUI

extension View {
    func card(_ alignment: Alignment = .topLeading) -> some View {
        padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .glass()
    }
}

struct OverviewPage: View {
    @Environment(Monitor.self) private var m
    var open: (Tab) -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                GaugeCard(icon: "cpu", title: "CPU", value: m.cpu.total,
                          detail: "User \(formatPercent(m.cpu.user)) · System \(formatPercent(m.cpu.system))",
                          history: m.history.cpu) {
                    Chip(text: formatTemp(m.temps.cpu), color: Nova.heat(m.temps.cpu))
                }
                .opens { open(.cpu) }
                GaugeCard(icon: "square.stack.3d.up", title: "GPU", value: m.gpu.usage,
                          detail: "\(formatMemory(m.gpu.memory)) in use",
                          history: m.history.gpu) {
                    Chip(text: formatTemp(m.temps.gpu), color: Nova.heat(m.temps.gpu))
                }
                .opens { open(.gpu) }
                GaugeCard(icon: "memorychip", title: "Memory", value: m.memory.fraction,
                          detail: "\(formatMemory(m.memory.used)) of \(formatMemory(m.memory.total))",
                          history: m.history.memory) {
                    PressureChip(level: m.memory.pressure)
                }
                .opens { open(.memory) }
            }
            HStack(spacing: 16) {
                NetworkCard().opens { open(.network) }
                DiskCard().opens { open(.disk) }
                TempsCard().opens { open(.sensors) }
            }
        }
    }
}

// a whole card you can click to open its tab
struct Opens: ViewModifier {
    var action: () -> Void
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(hovered ? 0.16 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture(perform: action)
            .onHover { hovered = $0 }
    }
}

extension View {
    func opens(_ action: @escaping () -> Void) -> some View {
        modifier(Opens(action: action))
    }
}

struct GaugeCard<Trailing: View>: View {
    var icon: String
    var title: String
    var value: Double
    var detail: String
    var history: [Double]
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 12) {
            CardHeader(icon: icon, title: title) { trailing }
            Ring(value: value, width: 9) {
                Text(formatPercent(value))
                    .font(.system(size: 32, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Nova.textHi)
            }
            .frame(width: 128, height: 128)
            Text(detail)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Nova.textMid)
            LineChart(series: [Series(color: Nova.sun, values: history)], window: 60, maxValue: 1)
                .frame(minHeight: 30, maxHeight: .infinity)
        }
        .card()
    }
}

struct PressureChip: View {
    var level: Int

    var body: some View {
        switch level {
        case 4: Chip(text: "Critical", color: Nova.red)
        case 2: Chip(text: "Warning", color: Nova.amber)
        default: Chip(text: "Normal", color: Nova.green)
        }
    }
}

struct RateView: View {
    var icon: String
    var color: Color
    var label: String
    var value: String
    var size: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Nova.textLo)
            }
            Text(value)
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(Nova.textHi)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NetworkCard: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "arrow.up.arrow.down", title: "Network") {
                Chip(text: m.net.ip.isEmpty ? "Offline" : m.net.kind)
            }
            HStack {
                RateView(icon: "arrow.down", color: Nova.down, label: "Download", value: formatRate(m.net.down))
                RateView(icon: "arrow.up", color: Nova.up, label: "Upload", value: formatRate(m.net.up))
            }
            LineChart(series: [Series(color: Nova.down, values: m.history.down),
                               Series(color: Nova.up, values: m.history.up)])
                .frame(minHeight: 30, maxHeight: .infinity)
            Text(m.net.ip.isEmpty ? "No connection" : "\(m.net.interface) · \(m.net.ip)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Nova.textLo)
        }
        .card()
    }
}

struct DiskCard: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "internaldrive", title: "Disk") {
                Chip(text: m.disk.name)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatBytes(m.disk.free))
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Nova.textHi)
                    Text("free of \(formatBytes(m.disk.total))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Nova.textMid)
                }
                Meter(value: m.disk.fraction)
            }
            HStack {
                RateView(icon: "circle.fill", color: Nova.down, label: "Read", value: formatRate(m.disk.read), size: 15)
                RateView(icon: "circle.fill", color: Nova.up, label: "Write", value: formatRate(m.disk.write), size: 15)
            }
            LineChart(series: [Series(color: Nova.down, values: m.history.read),
                               Series(color: Nova.up, values: m.history.write)])
                .frame(minHeight: 24, maxHeight: .infinity)
        }
        .card()
    }
}

struct TempsCard: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "thermometer.medium", title: "Temperatures") {
                Chip(text: fans)
            }
            TempRow(label: "CPU", value: m.temps.cpu)
            TempRow(label: "GPU", value: m.temps.gpu)
            TempRow(label: "SSD", value: m.temps.ssd)
            if m.temps.battery != nil {
                TempRow(label: "Battery", value: m.temps.battery)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var fans: String {
        guard m.temps.hasFans else { return "Fanless" }
        let rpm = m.temps.fans.max() ?? 0
        return rpm < 1 ? "Fans off" : "\(Int(rpm)) rpm"
    }
}

struct TempRow: View {
    var label: String
    var value: Double?

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Nova.textMid)
                Spacer()
                Text(formatTemp(value))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Nova.heat(value))
            }
            Meter(value: (value ?? 0) / 110, color: Nova.heat(value), height: 4)
        }
    }
}
