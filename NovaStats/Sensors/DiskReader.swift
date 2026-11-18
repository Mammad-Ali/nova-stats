import Foundation

struct Volume: Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let total: Double
    let free: Double
    let ejectable: Bool

    var fraction: Double { total > 0 ? max(total - free, 0) / total : 0 }
}

struct DiskSample {
    var volumes: [Volume] = []
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
    private var volumes: [Volume] = []
    private var volumesTime: TimeInterval = -100

    // after a drive is plugged in or ejected
    func refreshSoon() {
        volumesTime = -100
    }

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

        if now - volumesTime > 5 {
            volumes = mountedVolumes()
            volumesTime = now
        }
        s.volumes = volumes

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

    private func mountedVolumes() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsEjectableKey,
                                      .volumeIsRootFileSystemKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var root: Volume?
        var others: [Volume] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsBrowsable ?? true,
                  !url.path.hasPrefix("/Library/Developer"), let total = v.volumeTotalCapacity, total > 0 else { continue }
            let free = Double(v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0))
            let volume = Volume(path: url.path, name: v.volumeName ?? url.lastPathComponent, total: Double(total),
                                free: free, ejectable: v.volumeIsEjectable ?? false)
            if v.volumeIsRootFileSystem ?? false { root = volume } else { others.append(volume) }
        }
        return (root.map { [$0] } ?? []) + others.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
