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
        HStack(spacing: 16) {
            VStack(spacing: 16) {
                BenchmarkCard()
                    .frame(height: 330)
                BenchHistoryCard()
            }
            VStack(spacing: 16) {
                StressCard()
                    .frame(height: 330)
                StressChartCard()
            }
        }
    }
}

struct BenchmarkCard: View {
    @State private var lab = TestLab.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(icon: "speedometer", title: "Benchmark") {
                Text("about a minute")
                    .font(.system(size: 11))
                    .foregroundStyle(Nova.textLo)
                Button("Run all") { lab.runBenchmark() }
                    .buttonStyle(OutlineButton())
                    .disabled(lab.running)
                    .opacity(lab.running ? 0.4 : 1)
            }
            BenchRow(kind: .cpu, value: cpuText, spread: lab.latestCPU(\.cpuMulti)?.spread)
            BenchRow(kind: .gpu, value: lab.latest(\.gpuTflops).map { String(format: "%.2f TFLOPS", $0) },
                     spread: lab.latestSpread(\.gpuTflops, key: "gpu"))
            BenchRow(kind: .ai, value: lab.latest(\.aiTflops).map { String(format: "%.2f TFLOPS matrix", $0) },
                     spread: lab.latestSpread(\.aiTflops, key: "ai"))
            BenchRow(kind: .video, value: lab.latest(\.videoFps).map { String(format: "%.0f fps, 4K HEVC", $0) },
                     spread: lab.latestSpread(\.videoFps, key: "video"))
            BenchRow(kind: .memory, value: lab.latest(\.memory).map { String(format: "%.0f GB/s", $0) },
                     spread: lab.latestSpread(\.memory, key: "memory"))
            BenchRow(kind: .ssd, value: ssdText, spread: lab.latestSpread(\.ssdRead, key: "ssd"))
            Spacer(minLength: 0)
            Text("Each test runs several rounds and keeps the middle one. Scores use Nova Stats' own scale.")
                .font(.system(size: 11))
                .foregroundStyle(Nova.textLo)
        }
        .card()
    }

    private var cpuText: String? {
        guard let single = lab.latestCPU(\.cpuSingle), let multi = lab.latestCPU(\.cpuMulti) else { return nil }
        return "\(formatPoints(single.value)) one core · \(formatPoints(multi.value)) all"
    }

    private var ssdText: String? {
        guard let write = lab.latest(\.ssdWrite), let read = lab.latest(\.ssdRead) else { return nil }
        return "\(formatRate(write * 1e6)) write · \(formatRate(read * 1e6)) read"
    }
}

struct BenchRow: View {
    var kind: BenchKind
    var value: String?
    var spread: Double?
    @State private var lab = TestLab.shared

    var body: some View {
        let busy = lab.phase == .benchmark(kind)
        HStack(spacing: 12) {
            Text(kind.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Nova.textMid)
                .frame(width: 56, alignment: .leading)
            Text(busy ? "Running… \(formatPercent(lab.benchProgress))" : value ?? "Not run yet")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(busy ? Nova.sun : value == nil ? Nova.textLo : Nova.textHi)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let spread, value != nil, !busy {
                Text(String(format: "±%.1f%%", spread * 100))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Nova.textLo)
                    .help("How far the rounds were apart")
            }
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

enum HistoryMetric: String, CaseIterable {
    case cpu, gpu, ai, video, memory, ssd

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .ai: "AI"
        case .video: "Video"
        case .memory: "RAM"
        case .ssd: "SSD"
        }
    }

    func value(_ run: BenchResult) -> Double? {
        switch self {
        case .cpu: run.currentScale ? run.cpuMulti : nil
        case .gpu: run.gpuTflops
        case .ai: run.aiTflops
        case .video: run.videoFps
        case .memory: run.memory
        case .ssd: run.ssdRead
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .cpu: formatPoints(v)
        case .gpu, .ai: String(format: "%.2f TF", v)
        case .video: String(format: "%.0f fps", v)
        case .memory: String(format: "%.0f GB/s", v)
        case .ssd: formatRate(v * 1e6)
        }
    }
}

struct BenchHistoryCard: View {
    @State private var lab = TestLab.shared
    @AppStorage("historyMetric") private var metric = HistoryMetric.cpu
    @State private var picked: Date?

    var body: some View {
        let points = lab.benchmarks.reversed().compactMap { metric.value($0) }
        VStack(alignment: .leading, spacing: 10) {
            // the picker drops under the title when the window is narrow
            ViewThatFits(in: .horizontal) {
                HStack {
                    CardHeader(icon: "chart.xyaxis.line", title: "History")
                    PillPicker(options: HistoryMetric.allCases, label: \.title, selection: $metric, small: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    CardHeader(icon: "chart.xyaxis.line", title: "History")
                    PillPicker(options: HistoryMetric.allCases, label: \.title, selection: $metric, small: true)
                }
            }
            if points.count >= 2 {
                LineChart(series: [Series(color: Nova.sun, values: points)], window: points.count,
                          maxValue: (points.max() ?? 1) * 1.15, grid: metric.format)
                    .frame(height: 70)
            } else {
                Text(lab.benchmarks.isEmpty ? "Your benchmark runs show up here." : "Run the benchmark again to see a trend.")
                    .font(.system(size: 12))
                    .foregroundStyle(Nova.textLo)
            }
            if let latest = lab.benchmarks.first, let older = lab.benchmarks.first(where: { $0.date == picked }), older.date != latest.date {
                Text("Latest vs \(older.date.formatted(date: .abbreviated, time: .shortened)): \(comparison(latest, older))")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Nova.sun)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lab.benchmarks) { run in
                        Button {
                            picked = picked == run.date ? nil : run.date
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(run.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(picked == run.date ? Nova.sun : Nova.textHi)
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Compare the latest run with this one")
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .card()
    }

    private func summary(_ run: BenchResult) -> String {
        var parts: [String] = []
        if let s = run.cpuSingle, let m = run.cpuMulti {
            parts.append(run.currentScale ? "CPU \(formatPoints(s)) / \(formatPoints(m))" : "CPU (older scale)")
        }
        if let g = run.gpuTflops { parts.append(String(format: "GPU %.2f TF", g)) }
        if let a = run.aiTflops { parts.append(String(format: "AI %.2f TF", a)) }
        if let v = run.videoFps { parts.append(String(format: "Video %.0f fps", v)) }
        if let mem = run.memory { parts.append(String(format: "RAM %.0f GB/s", mem)) }
        if let w = run.ssdWrite, let r = run.ssdRead { parts.append("SSD \(formatRate(w * 1e6)) / \(formatRate(r * 1e6))") }
        return parts.joined(separator: " · ")
    }

    // percent change for every score both runs have
    private func comparison(_ latest: BenchResult, _ older: BenchResult) -> String {
        let parts = HistoryMetric.allCases.compactMap { m -> String? in
            guard let new = m.value(latest), let old = m.value(older), old > 0 else { return nil }
            let change = (new / old - 1) * 100
            return String(format: "%@ %@%.1f%%", m.title, change >= 0 ? "+" : "−", abs(change))
        }
        return parts.isEmpty ? "nothing to compare" : parts.joined(separator: " · ")
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
                Text("Benchmarking \(kind.title)… \(formatPercent(lab.benchProgress))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
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
