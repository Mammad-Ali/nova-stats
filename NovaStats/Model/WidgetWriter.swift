import Foundation
import WidgetKit

final class WidgetWriter {
    static let shared = WidgetWriter()

    private var lastWrite: Date?
    private var lastReload: Date?
    private let queue = DispatchQueue(label: "novastats.widgets", qos: .utility)

    // called after every sample, writes at most every 30 seconds
    func update(_ m: Monitor) {
        let now = Date()
        guard m.history.cpu.count >= 3 else { return }
        if let lastWrite, now.timeIntervalSince(lastWrite) < 30 { return }
        lastWrite = now

        var data = WidgetData()
        data.chip = m.cpuReader.name
        data.cpu = m.cpu.total
        data.gpu = m.gpu.usage
        data.memory = m.memory.fraction
        data.memoryUsed = m.memory.used
        data.memoryTotal = m.memory.total
        data.pressure = m.memory.pressure
        data.cpuTemp = m.temps.cpu
        data.gpuTemp = m.temps.gpu
        data.ssdTemp = m.temps.ssd
        data.diskFree = m.disk.free
        data.diskTotal = m.disk.total
        data.down = m.net.down
        data.up = m.net.up
        data.cpuHistory = downsample(m.history.cpu, seconds: 3600, points: 60)
        data.topApp = m.topCPU.first?.name
        data.topAppCPU = m.topCPU.first?.cpu ?? 0

        // macOS only allows so many widget refreshes a day, every 5 minutes is plenty
        let reload = lastReload.map { now.timeIntervalSince($0) >= 300 } ?? true
        if reload { lastReload = now }
        queue.async {
            data.save()
            if reload { WidgetCenter.shared.reloadAllTimelines() }
        }
    }
}
