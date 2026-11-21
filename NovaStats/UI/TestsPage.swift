import SwiftUI

// always 2,965: the app is in english, and some regions group thousands with a dot
func formatPoints(_ v: Double) -> String {
    v.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
}

func formatClock(_ seconds: TimeInterval) -> String {
    let s = max(Int(seconds), 0)
    return String(format: "%d:%02d", s / 60, s % 60)
}

func formatStressSpeed(_ v: Double, _ kind: StressKind) -> String {
    switch kind {
    case .cpu, .cpuGpu, .everything: "\(formatPoints(v)) points"
    case .gpu: String(format: "%.2f TFLOPS", v)
    case .ram: String(format: "%.0f GB/s", v)
    case .ssd: formatRate(v * 1e6)
    }
}

struct TestsPage: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                BenchmarkCard()
                StressCard()
            }
            .frame(height: 300)
            HStack(spacing: 16) {
                StressChartCard()
                BenchHistoryCard()
                    .frame(width: 400)
            }
        }
    }
}

struct BenchmarkCard: View {
    @State private var lab = TestLab.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "speedometer", title: "Benchmark") {
                Button("Run all") { lab.runBenchmark() }
                    .buttonStyle(OutlineButton())
                    .disabled(lab.running)
                    .opacity(lab.running ? 0.4 : 1)
            }
            BenchRow(kind: .cpu, value: cpuText)
            BenchRow(kind: .gpu, value: lab.latest(\.gpuTflops).map { String(format: "%.2f TFLOPS", $0) })
            BenchRow(kind: .memory, value: lab.latest(\.memory).map { String(format: "%.0f GB/s", $0) })
            BenchRow(kind: .ssd, value: ssdText)
            Spacer(minLength: 0)
            Text("Scores use Nova Stats' own scale. Quit other apps for steady results.")
                .font(.system(size: 11))
                .foregroundStyle(Nova.textLo)
        }
        .card()
    }

    private var cpuText: String? {
        guard let single = lab.latest(\.cpuSingle), let multi = lab.latest(\.cpuMulti) else { return nil }
        return "\(formatPoints(single)) one core · \(formatPoints(multi)) all"
    }

    private var ssdText: String? {
        guard let write = lab.latest(\.ssdWrite), let read = lab.latest(\.ssdRead) else { return nil }
        return "\(formatRate(write * 1e6)) write · \(formatRate(read * 1e6)) read"
    }
}

struct BenchRow: View {
    var kind: BenchKind
    var value: String?
    @State private var lab = TestLab.shared

    var body: some View {
        let busy = lab.phase == .benchmark(kind)
        HStack(spacing: 12) {
            Text(kind.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Nova.textMid)
                .frame(width: 64, alignment: .leading)
            Text(busy ? "Running…" : value ?? "Not run yet")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(busy ? Nova.sun : value == nil ? Nova.textLo : Nova.textHi)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Button("Run") { lab.runBenchmark([kind]) }
                .buttonStyle(SmallButton())
                .disabled(lab.running)
                .opacity(lab.running ? 0.4 : 1)
        }
    }
}

struct StressCard: View {
    @State private var lab = TestLab.shared
    @AppStorage("stressKind") private var kind = StressKind.cpu

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "flame", title: "Stress test") {
                PillPicker(options: [1, 5, 10, 0], label: { $0 == 0 ? "No limit" : "\($0) min" },
                           selection: $lab.minutes, small: true)
                    .disabled(lab.running)
            }
            Flow(spacing: 8) {
                ForEach(StressKind.allCases) { option in
                    ChoiceChip(title: option.title, selected: option == (lab.stressing ?? kind)) {
                        if !lab.running { kind = option }
                    }
                }
            }
            Text((lab.stressing ?? kind).detail)
                .font(.system(size: 12))
                .foregroundStyle(Nova.textMid)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                if let running = lab.stressing, let start = lab.stressStart {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatClock(Date().timeIntervalSince(start)) + (lab.stressLimit.map { " / " + formatClock($0) } ?? ""))
                            .font(.system(size: 26, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Nova.sun)
                        Text(formatStressSpeed(lab.speed, running))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(Nova.textMid)
                    }
                } else {
                    Text("Stops by itself above 110° or under 20% battery.")
                        .font(.system(size: 11))
                        .foregroundStyle(Nova.textLo)
                }
                Spacer()
                if lab.stressing != nil {
                    Button("Stop") { lab.stop() }
                        .buttonStyle(OutlineButton(active: true))
                } else {
                    Button("Start") { lab.startStress(kind) }
                        .buttonStyle(OutlineButton())
                        .disabled(lab.running)
                        .opacity(lab.running ? 0.4 : 1)
                }
            }
        }
        .card()
    }
}

// the live stress test, or the last one once it's over
struct StressChartCard: View {
    @State private var lab = TestLab.shared
    @Environment(Monitor.self) private var m

    var body: some View {
        let last = lab.stresses.first
        let live = lab.stressing != nil
        let speed = live ? lab.speedCurve : last?.speedCurve ?? []
        let temps = live ? lab.tempCurve : last?.tempCurve ?? []
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title(last))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Nova.textHi)
                Spacer()
                if live {
                    Chip(text: formatTemp(m.temps.cpu), color: Nova.heat(m.temps.cpu))
                    Chip(text: m.battery.systemWatts.map(formatWatts) ?? "—")
                    if GameMode.shared.hot { Chip(text: "macOS is slowing it down", color: Nova.amber) }
                } else if let last {
                    Chip(text: "peak " + formatTemp(last.peakTemp), color: Nova.heat(last.peakTemp))
                    Chip(text: "peak " + (last.peakPower.map(formatWatts) ?? "—"))
                    Chip(text: dropText(last), color: last.speedDrop == nil ? Nova.textMid : last.speedDrop! > 0.05 ? Nova.amber : Nova.green)
                    if last.errors > 0 { Chip(text: "\(last.errors) memory errors", color: Nova.red) }
                }
            }
            if speed.count > 1 {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Legend(color: Nova.sun, label: "Speed, compared with the start")
                        LineChart(series: [Series(color: Nova.sun, values: speed)], window: speed.count,
                                  maxValue: max(speed.max() ?? 1, 1.05), grid: formatPercent)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Legend(color: Nova.red, label: "CPU temperature")
                        LineChart(series: [Series(color: Nova.red, values: temps)], window: max(temps.count, 2),
                                  maxValue: 110, grid: { formatTemp($0) })
                    }
                }
            } else {
                Text(live ? "Measuring…" : "Run a stress test to see how speed and temperature change as your Mac heats up.")
                    .font(.system(size: 13))
                    .foregroundStyle(Nova.textLo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .card()
    }

    private func title(_ last: StressResult?) -> String {
        if let kind = lab.stressing { return "\(kind.name), live" }
        guard let last else { return "Stress test" }
        let how = switch last.stoppedBy {
        case "time": "ran its full time"
        case "you": "stopped by you"
        default: "stopped: \(last.stoppedBy)"
        }
        return "Last: \(last.kind.name), \(formatClock(last.duration)), \(how)"
    }

    private func dropText(_ result: StressResult) -> String {
        guard let drop = result.speedDrop else { return "too short to compare" }
        return drop < 0.02 ? "kept full speed" : "slowed \(formatPercent(drop))"
    }
}

struct BenchHistoryCard: View {
    @State private var lab = TestLab.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "clock.arrow.circlepath", title: "Past benchmarks")
            if lab.benchmarks.isEmpty {
                Text("Your benchmark runs show up here, so you can compare them.")
                    .font(.system(size: 13))
                    .foregroundStyle(Nova.textLo)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(lab.benchmarks) { run in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Nova.textHi)
                                Spacer()
                                Text(run.onBattery ? "on battery" : "plugged in")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(run.onBattery ? Nova.amber : Nova.textLo)
                            }
                            Text(summary(run))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(Nova.textMid)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .card()
    }

    private func summary(_ run: BenchResult) -> String {
        var parts: [String] = []
        if let s = run.cpuSingle, let m = run.cpuMulti { parts.append("CPU \(formatPoints(s)) / \(formatPoints(m))") }
        if let g = run.gpuTflops { parts.append(String(format: "GPU %.2f TF", g)) }
        if let mem = run.memory { parts.append(String(format: "RAM %.0f GB/s", mem)) }
        if let w = run.ssdWrite, let r = run.ssdRead { parts.append("SSD \(formatRate(w * 1e6)) / \(formatRate(r * 1e6))") }
        return parts.joined(separator: " · ")
    }
}

// the tests a tab can start, shown in the dashboard header
struct TestActions: View {
    var tab: Tab
    @State private var lab = TestLab.shared
    @State private var ui = UIState.shared

    var body: some View {
        if lab.running {
            RunningBanner()
        } else if let message = lab.message {
            HStack(spacing: 8) {
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Nova.textHi)
                if tab != .tests {
                    Button("Results") { ui.tab = .tests }
                        .buttonStyle(SmallButton())
                }
                Button {
                    lab.clearMessage()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Nova.textLo)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
        } else {
            HStack(spacing: 8) {
                if let bench = benchmark {
                    Button("Benchmark") { lab.runBenchmark([bench]) }
                        .buttonStyle(SmallButton())
                }
                if let stress {
                    Button(stress == .everything ? "Max power test" : "Stress test") { lab.startStress(stress) }
                        .buttonStyle(SmallButton())
                }
            }
        }
    }

    private var benchmark: BenchKind? {
        switch tab {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .disk: .ssd
        default: nil
        }
    }

    private var stress: StressKind? {
        switch tab {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .ram
        case .disk: .ssd
        case .battery: .everything
        default: nil
        }
    }
}

struct RunningBanner: View {
    @State private var lab = TestLab.shared

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Nova.sun)
                .frame(width: 7, height: 7)
            switch lab.phase {
            case .benchmark(let kind):
                Text("Benchmarking \(kind.title)…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Nova.textHi)
            case .stress(let kind):
                Text("\(kind.name) · \(formatClock(Date().timeIntervalSince(lab.stressStart ?? Date()))) · \(formatStressSpeed(lab.speed, kind))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Nova.textHi)
                Button("Stop") { lab.stop() }
                    .buttonStyle(SmallButton(active: true))
            case .idle:
                EmptyView()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Nova.sun.opacity(0.4)))
    }
}

struct SmallButton: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? Color.black : .white)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(active ? Color.white : .white.opacity(configuration.isPressed ? 0.14 : 0.06)))
            .overlay(Capsule().strokeBorder(.white.opacity(active ? 0 : 0.3)))
            .contentShape(Capsule())
    }
}
