import Foundation

struct AppUsage: Identifiable {
    let id: String
    let name: String
    let path: String?
    var cpu = 0.0     // share of the whole cpu, 0...1
    var memory = 0.0  // bytes, same number Activity Monitor shows
}

// groups processes by the app they belong to, so Chrome and all of its
// helpers show up as one "Google Chrome"
final class ProcessReader {
    private var lastTimes: [pid_t: UInt64] = [:]
    private var lastSample: UInt64 = 0
    private var names: [pid_t: (key: String, name: String, path: String?)] = [:]
    private let tick: Double
    private let cores = Double(ProcessInfo.processInfo.activeProcessorCount)

    init() {
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)
        tick = Double(timebase.numer) / Double(timebase.denom)
    }

    func read() -> [AppUsage] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let found = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))

        let now = mach_absolute_time()
        let elapsed = Double(now &- lastSample) * tick
        var groups: [String: AppUsage] = [:]
        var times: [pid_t: UInt64] = [:]

        for pid in pids.prefix(found) where pid > 0 {
            var usage = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard ok == 0 else { continue } // other users' processes, we can't see those

            // these are mach ticks on apple silicon, not nanoseconds
            let total = usage.ri_user_time + usage.ri_system_time
            times[pid] = total
            var cpu = 0.0
            if lastSample > 0, elapsed > 0, let before = lastTimes[pid], total >= before {
                cpu = Double(total - before) * tick / elapsed / cores
            }

            let who = identity(pid)
            groups[who.key, default: AppUsage(id: who.key, name: who.name, path: who.path)].cpu += cpu
            groups[who.key]?.memory += Double(usage.ri_phys_footprint)
        }

        lastTimes = times
        lastSample = now
        names = names.filter { times[$0.key] != nil }
        return Array(groups.values)
    }

    private func identity(_ pid: pid_t) -> (key: String, name: String, path: String?) {
        if let known = names[pid] { return known }

        var buf = [CChar](repeating: 0, count: 4096)
        let path = proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? cString(buf) : ""
        let result: (String, String, String?)
        if let range = path.range(of: ".app/") {
            // the first .app in the path is the app the user knows
            let app = String(path[..<range.lowerBound]) + ".app"
            var name = FileManager.default.displayName(atPath: app)
            if name.hasSuffix(".app") { name.removeLast(4) }
            result = (app, name, app)
        } else {
            var short = [CChar](repeating: 0, count: 256)
            proc_name(pid, &short, UInt32(short.count))
            let name = cString(short).isEmpty ? (path as NSString).lastPathComponent : cString(short)
            result = ("proc:" + name, name, nil)
        }
        names[pid] = result
        return result
    }
}
