import SwiftUI

struct MenuBarLabel: View {
    let monitor: Monitor
    let prefs: Prefs

    var body: some View {
        Image(nsImage: render())
    }

    @MainActor
    private func render() -> NSImage {
        let items = prefs.menuBarItems.isEmpty ? [Metric.cpu] : prefs.menuBarItems
        // read the values here, not inside ForEach: reads in there happen later,
        // while rendering, and swiftui wouldn't notice they changed
        let values = items.map { monitor.value($0, compact: true) }
        let graph = prefs.menuBarGraph ? Array(monitor.history.cpu.suffix(MiniGraph.bars)) : []
        let view = HStack(spacing: 8) {
            if prefs.menuBarGraph {
                MiniGraph(values: graph)
                    .frame(width: 34, height: 16)
            }
            ForEach(items.indices, id: \.self) { i in
                let metric = items[i]
                HStack(spacing: 3) {
                    Image(systemName: metric.icon)
                        .font(.system(size: metric.isTemp || metric == .download || metric == .upload ? 10 : 12, weight: .medium))
                    Text(values[i])
                        .frame(width: metric == .download || metric == .upload ? 36 : valueWidth(metric) - 4, alignment: .trailing)
                }
            }
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(.black)
        .fixedSize()

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}

// tiny cpu history for the menu bar, drawn black so macOS can tint it
struct MiniGraph: View {
    static let bars = 12
    var values: [Double]

    var body: some View {
        Canvas { ctx, size in
            let frame = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3)
            ctx.stroke(frame, with: .color(.black.opacity(0.45)), lineWidth: 1)
            let step = (size.width - 4) / CGFloat(Self.bars)
            let start = Self.bars - values.count
            for (i, v) in values.enumerated() {
                let h = max((size.height - 4) * CGFloat(min(max(v, 0), 1)), 1)
                let rect = CGRect(x: 2 + CGFloat(start + i) * step, y: size.height - 2 - h, width: step - 0.6, height: h)
                ctx.fill(Path(rect), with: .color(.black))
            }
        }
    }
}

struct MenuPanel: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Nova Stats")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Nova.sun)
                Spacer()
                Text("up \(formatUptime(m.uptime))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Nova.textLo)
            }

            VStack(spacing: 12) {
                PanelRow(icon: "cpu", label: "CPU", value: formatPercent(m.cpu.total), fraction: m.cpu.total)
                PanelRow(icon: "square.stack.3d.up", label: "GPU", value: formatPercent(m.gpu.usage), fraction: m.gpu.usage)
                PanelRow(icon: "memorychip", label: "Memory", value: formatMemory(m.memory.used), fraction: m.memory.fraction)
                PanelRow(icon: "internaldrive", label: "Disk", value: "\(formatBytes(m.disk.free)) free", fraction: m.disk.fraction)
            }
            .padding(14)
            .glass(16)

            HStack {
                RateView(icon: "arrow.down", color: Nova.down, label: "Download", value: formatRate(m.net.down), size: 14)
                RateView(icon: "arrow.up", color: Nova.up, label: "Upload", value: formatRate(m.net.up), size: 14)
            }
            .padding(14)
            .glass(16)

            HStack {
                PanelTemp(label: "CPU", value: m.temps.cpu)
                PanelTemp(label: "GPU", value: m.temps.gpu)
                PanelTemp(label: "SSD", value: m.temps.ssd)
            }
            .padding(14)
            .glass(16)

            HStack(spacing: 10) {
                Button {
                    Windows.shared.showDashboard()
                } label: {
                    Text("Dashboard")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButton())

                Button {
                    Prefs.shared.showHUD.toggle()
                } label: {
                    Image(systemName: "rectangle.topthird.inset.filled")
                }
                .buttonStyle(OutlineButton(active: Prefs.shared.showHUD))
                .help(Prefs.shared.showHUD ? "Hide the HUD" : "Show the HUD")

                Button {
                    Windows.shared.showSettings()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(OutlineButton())
                .help("Settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(OutlineButton())
                .help("Quit Nova Stats")
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(.black)
        .preferredColorScheme(.dark)
    }
}

struct PanelRow: View {
    var icon: String
    var label: String
    var value: String
    var fraction: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Nova.textMid)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Nova.textMid)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Nova.textHi)
            }
            Meter(value: fraction, height: 4)
        }
    }
}

struct PanelTemp: View {
    var label: String
    var value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Nova.textLo)
            Text(formatTemp(value))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(Nova.heat(value))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Nova's main button: thin white outline on black, no glow
struct OutlineButton: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? Color.black : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(active ? Color.white : .white.opacity(configuration.isPressed ? 0.12 : 0.0001)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.55)))
            .contentShape(Rectangle())
    }
}
