import Foundation
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
    @ObservationIgnored private let queue = DispatchQueue(label: "novastats.sampler", qos: .utility)
    @ObservationIgnored private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        sample()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        queue.async { [self] in
            if tempReader == nil { tempReader = TempReader() }
            let cpu = cpuReader.read()
            let gpu = gpuReader.read()
            let memory = memoryReader.read()
            let disk = diskReader.read()
            let net = netReader.read()
            let temps = tempReader?.read() ?? TempSample()
            let uptime = ProcessInfo.processInfo.systemUptime
            let apps = processReader.read()
            let topCPU = Array(apps.sorted { $0.cpu > $1.cpu }.prefix(10))
            let topMemory = Array(apps.sorted { $0.memory > $1.memory }.prefix(10))

            DispatchQueue.main.async { [self] in
                self.cpu = cpu
                self.gpu = gpu
                self.memory = memory
                self.disk = disk
                self.net = net
                self.temps = temps
                self.uptime = uptime
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
                history = h
                Alerts.shared.check(self)
                WidgetWriter.shared.update(self)
            }
        }
    }
}
