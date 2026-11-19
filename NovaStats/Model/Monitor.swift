import AppKit
import Observation

struct History {
    static let limit = 3600

    var cpu: [Double] = []
    var gpu: [Double] = []
    var memory: [Double] = []
    var down: [Double] = []
    var up: [Double] = []
    var read: [Double] = []
    var write: [Double] = []
    var cpuTemp: [Double] = []
    var gpuTemp: [Double] = []
    var power: [Double] = []

    fileprivate static func push(_ list: inout [Double], _ value: Double) {
        list.append(value)
        if list.count > limit { list.removeFirst(list.count - limit) }
    }
}

@Observable
final class Monitor {
    static let shared = Monitor()

    var cpu = CPUSample()
    var gpu = GPUSample()
    var memory = MemorySample()
    var disk = DiskSample()
    var net = NetSample()
    var temps = TempSample()
    var battery = BatterySample()
    var history = History()
    var uptime: TimeInterval = 0
    var topCPU: [AppUsage] = []
    var topMemory: [AppUsage] = []

    @ObservationIgnored let cpuReader = CPUReader()
    @ObservationIgnored let gpuReader = GPUReader()
    @ObservationIgnored let machine = Host.current().localizedName ?? "This Mac"
    @ObservationIgnored let macOS = ProcessInfo.processInfo.operatingSystemVersionString
        .replacingOccurrences(of: "Version ", with: "")
        .components(separatedBy: " (").first ?? ""
    @ObservationIgnored private let memoryReader = MemoryReader()
    @ObservationIgnored private let diskReader = DiskReader()
    @ObservationIgnored private let netReader = NetworkReader()
    @ObservationIgnored private let processReader = ProcessReader()
    @ObservationIgnored private var tempReader: TempReader? // made on the sampler queue
    @ObservationIgnored private let batteryReader = BatteryReader()
    @ObservationIgnored private var mountObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var screenAsleep = false
    @ObservationIgnored private let queue = DispatchQueue(label: "novastats.sampler", qos: .utility)
    @ObservationIgnored private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            mountObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                queue.async { self.diskReader.refreshSoon() }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        mountObservers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screenAsleep = true
        })
        mountObservers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screenAsleep = false
        })
        let distributed = DistributedNotificationCenter.default()
        mountObservers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenAsleep = true
        })
        mountObservers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenAsleep = false
        })
        sample()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        t.tolerance = 0.25 // lets macOS line our wakeups up with others
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // what someone can see decides how often the costly readers run
    private struct Needs {
        var dashboard = false
        var tab = Tab.overview
        var metrics: Set<Metric> = []
        var gaming = false

        func shows(_ wanted: Metric...) -> Bool { !metrics.isDisjoint(with: wanted) }
        func on(_ tabs: Tab...) -> Bool { dashboard && tabs.contains(tab) }
    }

    @ObservationIgnored private var lastRead: [String: TimeInterval] = [:] // sampler queue only
    @ObservationIgnored private var held = (gpu: GPUSample(), disk: DiskSample(), temps: TempSample(),
                                            battery: BatterySample(), topCPU: [AppUsage](), topMemory: [AppUsage]())

    private func currentNeeds() -> Needs {
        var needs = Needs()
        let prefs = Prefs.shared
        let game = GameMode.shared
        needs.dashboard = Windows.shared.dashboardOnScreen && !screenAsleep
        needs.tab = UIState.shared.tab
        needs.gaming = game.active
        if !screenAsleep {
            if prefs.showMenuBar { needs.metrics.formUnion(prefs.menuBarItems) }
            if game.overlayVisible { needs.metrics.formUnion(prefs.hudItems) }
        }
        return needs
    }

    // true when the reader should run now: every tick while live, else every `slow` seconds
    private func due(_ name: String, live: Bool, slow: TimeInterval, now: TimeInterval) -> Bool {
        if !live, let last = lastRead[name], now - last < slow { return false }
        lastRead[name] = now
        return true
    }

    private func sample() {
        let needs = currentNeeds()
        queue.async { [self] in
            if tempReader == nil { tempReader = TempReader() }
            let now = ProcessInfo.processInfo.systemUptime

            // cheap, always live: the menu bar and alerts lean on these
            let cpu = cpuReader.read()
            let memory = memoryReader.read()
            let net = netReader.read()

            if due("gpu", live: needs.dashboard || needs.gaming || needs.shows(.gpu), slow: 5, now: now) {
                held.gpu = gpuReader.read()
            }
            let everything = needs.dashboard || needs.gaming || needs.shows(.gpuTemp, .ssdTemp)
            if due("temps", live: everything || needs.shows(.cpuTemp), slow: 5, now: now) {
                // everything else every 5 seconds even when only the cpu number shows
                let full = everything || due("allTemps", live: false, slow: 5, now: now)
                tempReader?.read(into: &held.temps, everything: full, list: needs.on(.sensors))
            }
            if due("disk", live: needs.on(.overview, .disk) || needs.shows(.diskFree), slow: 5, now: now) {
                held.disk = diskReader.read(volumes: needs.on(.disk))
            }
            if due("power", live: needs.on(.battery) || needs.gaming || needs.shows(.power), slow: 5, now: now) {
                batteryReader.readPower(into: &held.battery)
            }
            if due("battery", live: needs.on(.battery) || needs.shows(.battery), slow: 30, now: now) {
                batteryReader.readBattery(into: &held.battery)
            }
            if due("apps", live: needs.on(.memory), slow: 10, now: now) {
                let apps = processReader.read()
                held.topCPU = Array(apps.sorted { $0.cpu > $1.cpu }.prefix(10))
                held.topMemory = Array(apps.sorted { $0.memory > $1.memory }.prefix(10))
            }
            let gpu = held.gpu, disk = held.disk, temps = held.temps, battery = held.battery
            let topCPU = held.topCPU, topMemory = held.topMemory

            DispatchQueue.main.async { [self] in
                self.cpu = cpu
                self.gpu = gpu
                self.memory = memory
                self.disk = disk
                self.net = net
                self.temps = temps
                self.battery = battery
                self.uptime = now
                self.topCPU = topCPU
                self.topMemory = topMemory

                var h = history
                History.push(&h.cpu, cpu.total)
                History.push(&h.gpu, gpu.usage)
                History.push(&h.memory, memory.fraction)
                History.push(&h.down, net.down)
                History.push(&h.up, net.up)
                History.push(&h.read, disk.read)
                History.push(&h.write, disk.write)
                History.push(&h.cpuTemp, temps.cpu ?? 0)
                History.push(&h.gpuTemp, temps.gpu ?? 0)
                History.push(&h.power, battery.systemWatts ?? 0)
                history = h
                Alerts.shared.check(self)
                GameMode.shared.record(self)
                WidgetWriter.shared.update(self)
            }
        }
    }
}
