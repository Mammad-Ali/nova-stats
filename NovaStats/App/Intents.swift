import AppIntents
import Foundation

// actions for siri and the shortcuts app. they run inside nova stats, which
// macOS starts first if it isn't running

extension Monitor {
    // right after launch the first readings take a moment
    @MainActor
    func ready() async -> Monitor {
        for _ in 0..<30 where history.cpu.count < 2 || temps.cpu == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return self
    }
}

struct TemperatureIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Mac temperature"
    static var description = IntentDescription("Tells you how hot the Mac's CPU and GPU are.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let m = await Monitor.shared.ready()
        let cpu = m.temps.cpu ?? 0
        let gpu = m.temps.gpu.map { " and the GPU at \(formatTempWithUnit($0))" } ?? ""
        let hot = GameMode.shared.hot ? " It's hot enough that macOS is slowing it down." : ""
        return .result(value: cpu, dialog: "The CPU is at \(formatTempWithUnit(cpu))\(gpu).\(hot)")
    }
}

struct CheckMacIntent: AppIntent {
    static var title: LocalizedStringResource = "Check my Mac"
    static var description = IntentDescription("CPU, GPU, memory, temperature and free space in one sentence.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let m = await Monitor.shared.ready()
        var text = "CPU \(formatPercent(m.cpu.total)), GPU \(formatPercent(m.gpu.usage)), memory \(formatPercent(m.memory.fraction))"
        if let t = m.temps.cpu { text += ", \(formatTempWithUnit(t))" }
        text += ", \(formatBytes(m.disk.free)) free"
        if m.battery.present { text += ", battery \(formatPercent(m.battery.percent))" }
        text += "."
        return .result(value: text, dialog: "\(text)")
    }
}

struct StartGameModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Start game mode"
    static var description = IntentDescription("Shows the overlay over your game and records a session report.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if !GameMode.shared.active { GameMode.shared.toggle() }
        return .result(dialog: "Game mode is on.")
    }
}

struct StopGameModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop game mode"
    static var description = IntentDescription("Hides the overlay and shows the session report.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if GameMode.shared.active { GameMode.shared.stop() }
        return .result(dialog: "Game mode is off.")
    }
}

struct BenchmarkIntent: AppIntent {
    static var title: LocalizedStringResource = "Run benchmark"
    static var description = IntentDescription("Runs the full benchmark in Nova Stats. It takes about a minute.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !TestLab.shared.running else {
            return .result(dialog: "A test is already running.")
        }
        UIState.shared.tab = .tests
        Windows.shared.showDashboard()
        TestLab.shared.runBenchmark()
        return .result(dialog: "The benchmark is running. It takes about a minute.")
    }
}

struct NovaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TemperatureIntent(),
                    phrases: ["How hot is my Mac in \(.applicationName)", "Check temperature with \(.applicationName)"],
                    shortTitle: "Temperature", systemImageName: "thermometer.medium")
        AppShortcut(intent: CheckMacIntent(),
                    phrases: ["Check my Mac with \(.applicationName)", "How is my Mac doing in \(.applicationName)"],
                    shortTitle: "Check my Mac", systemImageName: "gauge.with.dots.needle.33percent")
        AppShortcut(intent: StartGameModeIntent(),
                    phrases: ["Start game mode in \(.applicationName)"],
                    shortTitle: "Start game mode", systemImageName: "gamecontroller")
        AppShortcut(intent: StopGameModeIntent(),
                    phrases: ["Stop game mode in \(.applicationName)"],
                    shortTitle: "Stop game mode", systemImageName: "gamecontroller")
        AppShortcut(intent: BenchmarkIntent(),
                    phrases: ["Run a benchmark in \(.applicationName)"],
                    shortTitle: "Run benchmark", systemImageName: "speedometer")
    }
}
