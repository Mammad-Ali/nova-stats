import SwiftUI

extension Monitor {
    func value(_ metric: Metric, compact: Bool = false) -> String {
        switch metric {
        case .cpu: formatPercent(cpu.total)
        case .gpu: formatPercent(gpu.usage)
        case .memory: formatPercent(memory.fraction)
        case .cpuTemp: formatTemp(temps.cpu)
        case .gpuTemp: formatTemp(temps.gpu)
        case .ssdTemp: formatTemp(temps.ssd)
        case .download: compact ? formatRateShort(net.down) : formatRate(net.down)
        case .upload: compact ? formatRateShort(net.up) : formatRate(net.up)
        case .diskFree: formatBytes(disk.free)
        case .battery: battery.present ? formatPercent(battery.percent) : "—"
        case .power: battery.systemWatts.map(formatWatts) ?? "—"
        }
    }

    func color(_ metric: Metric) -> Color {
        switch metric {
        case .cpuTemp: Nova.heat(temps.cpu)
        case .gpuTemp: Nova.heat(temps.gpu)
        case .ssdTemp: Nova.heat(temps.ssd)
        default: Nova.textHi
        }
    }
}

// keeps the values from shoving each other around every second
func valueWidth(_ metric: Metric) -> CGFloat {
    switch metric {
    case .cpu, .gpu, .memory: 34
    case .cpuTemp, .gpuTemp, .ssdTemp: 28
    case .download, .upload: 66
    case .diskFree: 56
    case .battery: 34
    case .power: 46
    }
}

final class HUDController {
    static let shared = HUDController()

    private var panel: NSPanel?
    private var screenObserver: NSObjectProtocol?
    private var lastSize: CGSize?

    func refresh() {
        let prefs = Prefs.shared
        guard GameMode.shared.overlayVisible, !prefs.hudItems.isEmpty else {
            panel?.orderOut(nil)
            panel = nil
            return
        }
        if panel == nil { panel = makePanel() }
        place(lastSize)
        panel?.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true // clicks go straight through to whatever is below
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: HUDView { [weak self] size in self?.place(size) }
            .environment(Monitor.shared))
        host.sizingOptions = [] // we size the panel ourselves, otherwise it drifts off the corner
        panel.contentView = host

        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.place(self?.lastSize)
            }
        }
        return panel
    }

    private func place(_ measured: CGSize?) {
        guard let panel, let content = panel.contentView, let screen = NSScreen.screens.first else { return }
        let size = measured ?? content.fittingSize
        lastSize = measured ?? lastSize
        let area = screen.visibleFrame
        let margin: CGFloat = 12
        let x: CGFloat, y: CGFloat
        switch Prefs.shared.hudCorner {
        case .topLeft: (x, y) = (area.minX + margin, area.maxY - margin - size.height)
        case .topRight: (x, y) = (area.maxX - margin - size.width, area.maxY - margin - size.height)
        case .bottomLeft: (x, y) = (area.minX + margin, area.minY + margin)
        case .bottomRight: (x, y) = (area.maxX - margin - size.width, area.minY + margin)
        }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

struct HUDView: View {
    @Environment(Monitor.self) private var m
    var onResize: (CGSize) -> Void

    var body: some View {
        let prefs = Prefs.shared
        Group {
            if prefs.hudLayout == .row {
                HStack(spacing: 14) {
                    ForEach(prefs.hudItems) { HUDItem(metric: $0) }
                    if GameMode.shared.hot { HotWarning() }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(prefs.hudItems) { HUDItem(metric: $0) }
                    if GameMode.shared.hot { HotWarning() }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        // no box behind it: a thin dark outline round every letter keeps it
        // readable over any window, like a game's fps counter
        .shadow(color: .black, radius: 0, x: 1, y: 0)
        .shadow(color: .black, radius: 0, x: -1, y: 0)
        .shadow(color: .black, radius: 0, x: 0, y: 1)
        .shadow(color: .black, radius: 0, x: 0, y: -1)
        .shadow(color: .black.opacity(0.7), radius: 3)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onResize($0) }
        .environment(\.colorScheme, .dark)
    }
}

struct HUDItem: View {
    @Environment(Monitor.self) private var m
    var metric: Metric

    var body: some View {
        HStack(spacing: 5) {
            if metric.isTemp || metric == .download || metric == .upload {
                Image(systemName: metric.icon)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(metric == .download ? Nova.down : metric == .upload ? Nova.up : Nova.textMid)
            }
            if !metric.short.isEmpty {
                Text(metric.short)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Nova.textMid)
                    .fixedSize()
            }
            Text(m.value(metric))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(m.color(metric))
                .frame(width: valueWidth(metric), alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// shown while macOS is holding the mac back because it's too hot
struct HotWarning: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
            Text("HOT · slowing down")
                .font(.system(size: 11, weight: .heavy))
        }
        .foregroundStyle(Nova.red)
        .fixedSize()
    }
}
