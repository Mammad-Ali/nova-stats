import SwiftUI

enum Tab: Int, CaseIterable, Identifiable {
    case overview, cpu, gpu, memory, disk, network, battery, sensors

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .network: "Network"
        case .battery: "Battery"
        case .sensors: "Sensors"
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "arrow.up.arrow.down"
        case .battery: "battery.75percent"
        case .sensors: "thermometer.medium"
        }
    }
}

struct DashboardView: View {
    @Environment(Monitor.self) private var monitor
    @AppStorage("lastTab") private var tab = Tab.overview
    @State private var sky = Sky()

    var body: some View {
        ZStack {
            if Prefs.shared.starfield {
                Starfield(sky: sky, level: monitor.cpu.total)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.top, 34)
                    .padding(.bottom, 18)

                Group {
                    switch tab {
                    case .overview: OverviewPage { tab = $0 }
                    case .cpu: CPUPage()
                    case .gpu: GPUPage()
                    case .memory: MemoryPage()
                    case .disk: DiskPage()
                    case .network: NetworkPage()
                    case .battery: BatteryPage()
                    case .sensors: SensorsPage()
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                .id(tab)

                TabBar(selection: $tab)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 14)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): sky.cursor = point
            case .ended: sky.cursor = nil
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tab)
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tab == .overview ? "Nova Stats" : tab.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Nova.sun)
                Text("\(monitor.cpuReader.name) · \(monitor.cpuReader.superCores + monitor.cpuReader.efficiencyCores)-core CPU · \(monitor.gpuReader.cores)-core GPU · \(formatMemory(monitor.memory.total))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Nova.textMid)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(monitor.machine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Nova.textHi)
                Text("macOS \(monitor.macOS) · up \(formatUptime(monitor.uptime))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Nova.textLo)
            }
            HStack(spacing: 4) {
                HeaderButton(icon: "questionmark.circle", help: "Questions and help") {
                    Windows.shared.showSettings(.about)
                }
                HeaderButton(icon: "slider.horizontal.3", help: "Settings  ⌘,") {
                    Windows.shared.showSettings()
                }
            }
            .padding(.leading, 14)
            .alignmentGuide(.lastTextBaseline) { $0[.bottom] - 4 }
        }
    }
}

struct TabBar: View {
    @Binding var selection: Tab
    @State private var hovered: Tab?
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                let active = tab == selection
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { selection = tab }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(active ? Color.black : hovered == tab ? Nova.textHi : Nova.textMid)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(tab.rawValue + 1)")), modifiers: .command)
                .onHover { hovered = $0 ? tab : (hovered == tab ? nil : hovered) }
                .help("\(tab.title)  ⌘\(tab.rawValue + 1)")
            }
        }
        .padding(7)
        .frame(height: 66)
        .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .glass()
    }
}

// icon button like Nova's header ones: no frame, brighter under the mouse
struct HeaderButton: View {
    var icon: String
    var help: String
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(hovered ? Nova.textHi : Nova.textMid)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(hovered ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
