import Foundation

struct DiskSample {
    var name = "Macintosh HD"
    var total = 0.0
    var free = 0.0
    var read = 0.0
    var write = 0.0

    var used: Double { max(total - free, 0) }
    var fraction: Double { total > 0 ? used / total : 0 }
}

final class DiskReader {
    private var last: (read: Double, write: Double, time: TimeInterval)?
    private var space: (name: String, total: Double, free: Double)?
    private var spaceTime: TimeInterval = 0

    func read() -> DiskSample {
        var s = DiskSample()
        let now = ProcessInfo.processInfo.systemUptime

        // free space barely moves, no need to ask every second
        if space == nil || now - spaceTime > 15 {
            let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
            if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) {
                space = (v.volumeName ?? s.name,
                         Double(v.volumeTotalCapacity ?? 0),
                         Double(v.volumeAvailableCapacityForImportantUsage ?? 0))
                spaceTime = now
            }
        }
        if let space {
            s.name = space.name
            s.total = space.total
            s.free = space.free
        }

        var read = 0.0, write = 0.0
        for case let stats as [String: Any] in ioProperty("IOBlockStorageDriver", "Statistics") {
            read += Double(stats["Bytes (Read)"] as? Int ?? 0)
            write += Double(stats["Bytes (Write)"] as? Int ?? 0)
        }
        if let last, now > last.time {
            s.read = max(read - last.read, 0) / (now - last.time)
            s.write = max(write - last.write, 0) / (now - last.time)
        }
        last = (read, write, now)
        return s
    }
}
