import Foundation
import Observation

enum StressKind: String, CaseIterable, Identifiable, Codable {
    case cpu, gpu, cpuGpu, ram, ssd, everything

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .cpuGpu: "CPU + GPU"
        case .ram: "RAM"
        case .ssd: "SSD"
        case .everything: "Everything"
        }
    }

    var detail: String {
        switch self {
        case .cpu: "Heavy math on every core."
        case .gpu: "A Metal shader keeps every GPU core busy."
        case .cpuGpu: "Both at once, like a demanding game."
        case .ram: "Fills free memory over and over and checks every byte comes back right."
        case .ssd: "Reads a test file as fast as the SSD can. Only reads, so it doesn't wear the SSD."
        case .everything: "CPU, GPU, RAM and SSD at once: the most power your Mac can draw."
        }
    }

    // what the test is called in messages and the banner
    var name: String {
        self == .everything ? "Max power test" : "\(title) stress test"
    }

    var unit: String {
        switch self {
        case .cpu, .cpuGpu, .everything: "points"
        case .gpu: "TFLOPS"
        case .ram: "GB/s"
        case .ssd: "MB/s"
        }
    }
}

enum BenchKind: String, CaseIterable, Identifiable {
    case cpu, gpu, ai, video, memory, ssd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .ai: "AI"
        case .video: "Video"
        case .memory: "Memory"
        case .ssd: "SSD"
        }
    }
}

struct BenchResult: Codable, Identifiable {
    var id: Date { date }
    var date = Date()
    var onBattery = false
    var cpuSingle: Double?
    var cpuMulti: Double?
    var gpuTflops: Double?
    var aiTflops: Double?
    var videoFps: Double?
    var memory: Double? // GB/s
    var ssdWrite: Double? // MB/s
    var ssdRead: Double?
    var spreads: [String: Double]? // how far the rounds were apart, ±
    var scale: Int? // 2 since the three-kernel cpu score; older cpu scores don't compare

    var currentScale: Bool { scale == 2 }
}

struct StressResult: Codable, Identifiable {
    var id: Date { start }
    var kind: StressKind
    var start: Date
    var duration: TimeInterval
    var peakTemp: Double?
    var peakPower: Double?
    var speedDrop: Double? // how much slower the end was than the start, 0...1
    var hotSeconds: Int
    var errors: Int
    var stoppedBy: String
    var speedCurve: [Double]
    var tempCurve: [Double]
}

// one core of an M5 is 3,000 points: each kernel's speed is compared with
// that core's, and the score is the geometric mean of the three
enum CPUReference {
    static func rate(_ kernel: CPUKernel) -> Double {
        switch kernel {
        case .integer: 7.0e8
        case .float: 7.65e8
        case .sort: 2.626e4
        }
    }

    static func score(_ ratios: [Double]) -> Double {
        guard !ratios.isEmpty else { return 0 }
        return 3000 * exp(ratios.map { log(max($0, 1e-9)) }.reduce(0, +) / Double(ratios.count))
    }
}

// the stress test runs the float kernel, shown in the same points
func cpuPoints(_ iterationsPerSecond: Double) -> Double {
    iterationsPerSecond / CPUReference.rate(.float) * 3000
}

// runs one test at a time: a benchmark or a stress test
@Observable
final class TestLab {
    static let shared = TestLab()

    enum Phase: Equatable {
        case idle
        case benchmark(BenchKind)
        case stress(StressKind)
    }

    private(set) var phase = Phase.idle
    private(set) var benchProgress = 0.0
    private(set) var benchmarks: [BenchResult] = []
    private(set) var stresses: [StressResult] = []
    private(set) var stressStart: Date?
    private(set) var stressLimit: TimeInterval?
    private(set) var speed = 0.0 // the main workload, in its own unit
    private(set) var speedCurve: [Double] = [] // speed as a share of the starting speed
    private(set) var tempCurve: [Double] = []
    private(set) var errors = 0
    private(set) var message: String? // the last thing that happened, for the banner

    var minutes: Int {
        didSet { UserDefaults.standard.set(minutes, forKey: "stressMinutes") }
    }

    var running: Bool { phase != .idle }
    var benchmarking: Bool {
        if case .benchmark = phase { return true }
        return false
    }
    var stressing: StressKind? {
        if case .stress(let kind) = phase { return kind }
        return nil
    }

    @ObservationIgnored private var counters: [String: WorkCounter] = [:]
    @ObservationIgnored private var lastTick = 0.0
    @ObservationIgnored private var speeds: [Double] = []
    @ObservationIgnored private var peakTemp: Double?
    @ObservationIgnored private var peakPower: Double?
    @ObservationIgnored private var hotSeconds = 0
    @ObservationIgnored private var gpu: GPUWork?

    init() {
        minutes = UserDefaults.standard.object(forKey: "stressMinutes") as? Int ?? 5
        let d = UserDefaults.standard
        if let data = d.data(forKey: "benchResults"), let saved = try? JSONDecoder().decode([BenchResult].self, from: data) {
            benchmarks = saved
        }
        if let data = d.data(forKey: "stressResults"), let saved = try? JSONDecoder().decode([StressResult].self, from: data) {
            stresses = saved
        }
    }

    // the newest value of each benchmark, from whichever run measured it
    func latest<T>(_ value: KeyPath<BenchResult, T?>) -> T? {
        benchmarks.lazy.compactMap { $0[keyPath: value] }.first
    }

    // MARK: benchmark

    func runBenchmark(_ kinds: [BenchKind] = BenchKind.allCases) {
        guard !running, let first = kinds.first else { return }
        message = nil
        phase = .benchmark(first)
        benchProgress = 0
        let onBattery = Monitor.shared.battery.present && !Monitor.shared.battery.pluggedIn
        if gpu == nil { gpu = GPUWork() }
        let gpu = self.gpu

        Thread.detachNewThread { [self] in
            var result = BenchResult(onBattery: onBattery)
            result.scale = 2
            var spreads: [String: Double] = [:]
            let cores = ProcessInfo.processInfo.activeProcessorCount
            // the cpu has six parts (three kernels, one core and all), the rest one each
            let steps = Double(kinds.reduce(0) { $0 + ($1 == .cpu ? 6 : 1) })
            var step = 0.0
            func advance() {
                step += 1
                let progress = step / steps
                DispatchQueue.main.async { self.benchProgress = progress }
            }

            for (i, kind) in kinds.enumerated() {
                if i > 0 { Thread.sleep(forTimeInterval: 1.5) } // a short cool-down between tests
                DispatchQueue.main.async { self.phase = .benchmark(kind) }
                switch kind {
                case .cpu:
                    for threads in [1, cores] {
                        var ratios: [Double] = []
                        var widest = 0.0
                        for kernel in CPUKernel.allCases {
                            let rounds = CPUWork.rounds(threads: threads, kernel: kernel, count: 3, seconds: 1.2)
                            ratios.append(median(rounds) / CPUReference.rate(kernel))
                            widest = max(widest, spread(rounds))
                            advance()
                        }
                        if threads == 1 {
                            result.cpuSingle = CPUReference.score(ratios)
                            spreads["cpuSingle"] = widest
                        } else {
                            result.cpuMulti = CPUReference.score(ratios)
                            spreads["cpuMulti"] = widest
                        }
                    }
                case .gpu:
                    if let rounds = gpu?.rounds(count: 5, seconds: 1.5), !rounds.isEmpty {
                        result.gpuTflops = median(rounds)
                        spreads["gpu"] = spread(rounds)
                    }
                    advance()
                case .ai:
                    let rounds = MatrixWork.rounds(count: 5, seconds: 1)
                    result.aiTflops = median(rounds)
                    spreads["ai"] = spread(rounds)
                    advance()
                case .video:
                    let rounds = VideoWork.rounds(count: 4, seconds: 1.5)
                    if !rounds.isEmpty {
                        result.videoFps = median(rounds)
                        spreads["video"] = spread(rounds)
                    }
                    advance()
                case .memory:
                    let rounds = MemoryWork.rounds(count: 5, seconds: 1)
                    result.memory = median(rounds)
                    spreads["memory"] = spread(rounds)
                    advance()
                case .ssd:
                    if let speed = DiskWork.speed() {
                        result.ssdWrite = speed.write
                        result.ssdRead = median(speed.read)
                        spreads["ssd"] = spread(speed.read)
                    }
                    advance()
                }
            }
            result.spreads = spreads
            DispatchQueue.main.async {
                self.benchmarks.insert(result, at: 0)
                if self.benchmarks.count > 30 { self.benchmarks.removeLast(self.benchmarks.count - 30) }
                self.save()
                self.benchProgress = 1
                self.phase = .idle
                self.say(kinds.count == 1 ? "\(kinds[0].title) benchmark done" : "Benchmark done")
            }
        }
    }

    // the newest cpu score on today's scale
    func latestCPU(_ value: KeyPath<BenchResult, Double?>) -> (value: Double, spread: Double?)? {
        guard let run = benchmarks.first(where: { $0.currentScale && $0[keyPath: value] != nil }) else { return nil }
        let key = value == \BenchResult.cpuSingle ? "cpuSingle" : "cpuMulti"
        return (run[keyPath: value]!, run.spreads?[key])
    }

    // the spread that came with the newest value of a metric
    func latestSpread(_ value: KeyPath<BenchResult, Double?>, key: String) -> Double? {
        benchmarks.first { $0[keyPath: value] != nil }?.spreads?[key]
    }

    // MARK: stress

    func startStress(_ kind: StressKind) {
        guard !running else { return }
        let battery = Monitor.shared.battery
        if battery.present && !battery.pluggedIn && battery.percent < 0.2 {
            say("Battery is under 20%, plug in to run a stress test")
            return
        }
        message = nil
        counters = [:]
        speeds = []
        speedCurve = []
        tempCurve = []
        speed = 0
        errors = 0
        peakTemp = nil
        peakPower = nil
        hotSeconds = 0
        lastTick = ProcessInfo.processInfo.systemUptime

        let cores = ProcessInfo.processInfo.activeProcessorCount
        if [.cpu, .cpuGpu, .everything].contains(kind) {
            let counter = WorkCounter()
            CPUWork.start(threads: cores, counter: counter)
            counters["cpu"] = counter
        }
        if [.gpu, .cpuGpu, .everything].contains(kind) {
            if gpu == nil { gpu = GPUWork() }
            let counter = WorkCounter()
            gpu?.start(counter: counter)
            counters["gpu"] = counter
        }
        if [.ram, .everything].contains(kind) {
            // at most 4 GB, and well under what's free, so macOS doesn't start swapping
            let memory = Monitor.shared.memory
            let free = max(memory.total - memory.used, 0)
            let size = Int(min(4 * 1_073_741_824, free * 0.4))
            let counter = WorkCounter()
            MemoryWork.stress(bytes: max(size, 256 << 20), threads: kind == .ram ? 4 : 2, counter: counter)
            counters["ram"] = counter
        }
        if [.ssd, .everything].contains(kind) {
            let counter = WorkCounter()
            counters["ssd"] = counter
            DispatchQueue.global(qos: .userInitiated).async {
                if !DiskWork.stress(counter: counter) {
                    DispatchQueue.main.async {
                        if kind == .ssd { self.stopStress(reason: "not enough free space") }
                    }
                }
            }
        }
        stressStart = Date()
        stressLimit = minutes > 0 ? Double(minutes * 60) : nil
        phase = .stress(kind)
    }

    func stop() {
        if stressing != nil { stopStress(reason: "you") }
    }

    private func stopStress(reason: String) {
        guard let kind = stressing, let start = stressStart else { return }
        counters.values.forEach { $0.stop() }
        counters = [:]
        phase = .idle

        // compare the first and the last 20 seconds of real work
        var drop: Double?
        let warm = Array(speeds.dropFirst(3))
        if warm.count >= 40 {
            let head = warm.prefix(20).reduce(0, +) / 20
            let tail = warm.suffix(20).reduce(0, +) / 20
            if head > 0 { drop = max(0, 1 - tail / head) }
        }
        let result = StressResult(kind: kind, start: start, duration: Date().timeIntervalSince(start),
                                  peakTemp: peakTemp, peakPower: peakPower, speedDrop: drop,
                                  hotSeconds: hotSeconds, errors: errors, stoppedBy: reason,
                                  speedCurve: downsample(speedCurve, seconds: speedCurve.count, points: 120),
                                  tempCurve: downsample(tempCurve, seconds: tempCurve.count, points: 120))
        stresses.insert(result, at: 0)
        if stresses.count > 20 { stresses.removeLast(stresses.count - 20) }
        save()
        switch reason {
        case "time": say("\(kind.name) finished")
        case "you": say("\(kind.name) stopped")
        default: say("\(kind.name) stopped: \(reason)")
        }
    }

    // once a second from the monitor
    func tick(_ m: Monitor) {
        guard let kind = stressing, let start = stressStart else { return }
        let nowTime = ProcessInfo.processInfo.systemUptime
        let elapsed = max(nowTime - lastTick, 0.2)
        lastTick = nowTime

        var done: [String: Double] = [:]
        for (name, counter) in counters {
            done[name] = counter.take() / elapsed
            errors = max(errors, counter.errors)
        }
        speed = switch kind {
        case .cpu, .cpuGpu, .everything: cpuPoints(done["cpu"] ?? 0)
        case .gpu: (done["gpu"] ?? 0) / 1e12
        case .ram: (done["ram"] ?? 0) / 2e9
        case .ssd: (done["ssd"] ?? 0) / 1e6
        }
        speeds.append(speed)
        // the first two seconds are the workers starting up, so the chart and the
        // baseline (the best of the next ten) begin after them
        if speeds.count > 2 {
            let base = speeds.dropFirst(2).prefix(10).max() ?? 0
            speedCurve.append(base > 0 ? speed / base : 0)
        }
        if let t = m.temps.cpu {
            tempCurve.append(t)
            peakTemp = max(peakTemp ?? t, t)
        }
        if let w = m.battery.systemWatts { peakPower = max(peakPower ?? w, w) }
        if GameMode.shared.hot { hotSeconds += 1 }

        let battery = m.battery
        if let limit = stressLimit, Date().timeIntervalSince(start) >= limit {
            stopStress(reason: "time")
        } else if let t = m.temps.cpu, t >= 110 {
            stopStress(reason: "too hot")
        } else if battery.present && !battery.pluggedIn && battery.percent < 0.2 {
            stopStress(reason: "battery low")
        }
    }

    func clearMessage() {
        message = nil
    }

    // shown in the dashboard header for a few seconds, so it doesn't hide the tab's buttons for long
    private func say(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            if self?.message == text { self?.message = nil }
        }
    }

    private func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(benchmarks) { d.set(data, forKey: "benchResults") }
        if let data = try? JSONEncoder().encode(stresses) { d.set(data, forKey: "stressResults") }
    }
}
