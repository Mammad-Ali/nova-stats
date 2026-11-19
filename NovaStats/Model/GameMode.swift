import AppKit
import Observation

struct SessionReport: Codable, Identifiable {
    var id: Date { start }
    var game: String
    var start: Date
    var duration: TimeInterval
    var cpuAvg: Double
    var cpuPeak: Double
    var gpuAvg: Double
    var gpuPeak: Double
    var cpuTempAvg: Double?
    var cpuTempPeak: Double?
    var gpuTempAvg: Double?
    var gpuTempPeak: Double?
    var powerAvg: Double?
    var powerPeak: Double?
    var hotSeconds: Int
    var tempCurve: [Double] // cpu temperature over the session, about 120 points
}

// the overlay only shows while game mode is on. it starts by hand (menu bar,
// shortcut) or, if switched on in settings, when a game goes full screen
@Observable
final class GameMode {
    static let shared = GameMode()

    private(set) var active = false
    private(set) var startedAutomatically = false
    private(set) var hot = false // macOS is slowing the mac down because of heat
    private(set) var reports: [SessionReport] = []
    var overlayHidden = false {
        didSet { HUDController.shared.refresh() }
    }

    var overlayVisible: Bool { active && !overlayHidden }

    private struct Session {
        var start = Date()
        var cpu: [Double] = []
        var gpu: [Double] = []
        var cpuTemp: [Double] = []
        var gpuTemp: [Double] = []
        var power: [Double] = []
        var hotSeconds = 0
        var apps: [String: Int] = [:] // seconds each app was in front, to name the session
    }

    @ObservationIgnored private var session = Session()
    @ObservationIgnored private var watchTimer: Timer?
    @ObservationIgnored private var gamePID: pid_t?
    @ObservationIgnored private var awaySince: Date?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var activation: NSObjectProtocol?
    @ObservationIgnored private var gameCache: [String: Bool] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: "gameReports"),
           let saved = try? JSONDecoder().decode([SessionReport].self, from: data) {
            reports = saved
        }
        hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        observers.append(NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        })
    }

    // MARK: on and off

    func toggle() {
        active ? stop() : start(automatically: false)
    }

    // the overlay shortcut: shows game mode if it's off, else hides or shows the overlay
    func toggleOverlay() {
        if active {
            overlayHidden.toggle()
        } else {
            start(automatically: false)
        }
    }

    private func start(automatically: Bool, game: String? = nil) {
        guard !active else { return }
        session = Session()
        if let game { session.apps[game] = 1 }
        startedAutomatically = automatically
        overlayHidden = false
        active = true
        HUDController.shared.refresh()
    }

    func stop() {
        guard active else { return }
        active = false
        startedAutomatically = false
        gamePID = nil
        awaySince = nil
        HUDController.shared.refresh()

        // a few seconds of trying the button isn't worth a report
        guard let report = makeReport(), report.duration >= 30 else { return }
        reports.insert(report, at: 0)
        if reports.count > 10 { reports.removeLast(reports.count - 10) }
        if let data = try? JSONEncoder().encode(reports) {
            UserDefaults.standard.set(data, forKey: "gameReports")
        }
        ReportWindow.shared.show(report)
    }

    // MARK: recording, once a second from the monitor

    func record(_ m: Monitor) {
        guard active else { return }
        session.cpu.append(m.cpu.total)
        session.gpu.append(m.gpu.usage)
        if let t = m.temps.cpu { session.cpuTemp.append(t) }
        if let t = m.temps.gpu { session.gpuTemp.append(t) }
        if let w = m.battery.systemWatts { session.power.append(w) }
        if hot { session.hotSeconds += 1 }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier,
           front.bundleIdentifier != "com.apple.finder",
           let name = front.localizedName {
            session.apps[name, default: 0] += 1
        }
    }

    private func makeReport() -> SessionReport? {
        let s = session
        guard !s.cpu.isEmpty else { return nil }
        func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        return SessionReport(
            game: s.apps.max { $0.value < $1.value }?.key ?? "Game session",
            start: s.start,
            duration: Date().timeIntervalSince(s.start),
            cpuAvg: avg(s.cpu) ?? 0, cpuPeak: s.cpu.max() ?? 0,
            gpuAvg: avg(s.gpu) ?? 0, gpuPeak: s.gpu.max() ?? 0,
            cpuTempAvg: avg(s.cpuTemp), cpuTempPeak: s.cpuTemp.max(),
            gpuTempAvg: avg(s.gpuTemp), gpuTempPeak: s.gpuTemp.max(),
            powerAvg: avg(s.power), powerPeak: s.power.max(),
            hotSeconds: s.hotSeconds,
            tempCurve: downsample(s.cpuTemp, seconds: s.cpuTemp.count, points: 120))
    }

    // MARK: automatic start

    func updateWatching() {
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        watchTimer?.invalidate()
        watchTimer = nil
        guard Prefs.shared.gameAuto else {
            if startedAutomatically { stop() }
            return
        }
        activation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                       object: nil, queue: .main) { [weak self] _ in
            self?.check()
        }
        // full screen can start after the app comes to the front, so look again now and then
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.check() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
        check()
    }

    private func check() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, isGame(front), isFullScreen(front.processIdentifier) {
            awaySince = nil
            if !active {
                start(automatically: true, game: front.localizedName)
                gamePID = front.processIdentifier
            }
        } else if active && startedAutomatically {
            if let pid = gamePID, NSRunningApplication(processIdentifier: pid) == nil {
                stop() // the game quit
                return
            }
            // leaving the game for a moment shouldn't end the session
            awaySince = awaySince ?? Date()
            if Date().timeIntervalSince(awaySince!) > 20 { stop() }
        }
    }

    // apps that call themselves games, and anything steam installed
    private func isGame(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        if let known = gameCache[url.path] { return known }
        let category = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String ?? ""
        let game = category.contains("games") || url.path.contains("/steamapps/common/")
        gameCache[url.path] = game
        return game
    }

    // a normal-level window as big as a screen, real full screen or borderless
    private func isFullScreen(_ pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows where (window[kCGWindowOwnerPID as String] as? pid_t) == pid
            && (window[kCGWindowLayer as String] as? Int) == 0 {
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            // notched screens give full screen apps a bit less height
            if NSScreen.screens.contains(where: { rect.width >= $0.frame.width && rect.height >= $0.frame.height - 40 }) {
                return true
            }
        }
        return false
    }
}
