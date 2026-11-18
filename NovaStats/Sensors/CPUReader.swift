import Foundation

struct CPUSample {
    var total = 0.0
    var user = 0.0
    var system = 0.0
    var cores: [Double] = []
}

final class CPUReader {
    let name: String
    let superCores: Int
    let efficiencyCores: Int
    let superName: String
    let efficiencyName: String
    private var previous: [[UInt32]] = []

    init() {
        name = sysctlString("machdep.cpu.brand_string") ?? "Mac"
        superCores = sysctlInt("hw.perflevel0.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount
        efficiencyCores = sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        superName = sysctlString("hw.perflevel0.name") ?? "Performance"
        efficiencyName = sysctlString("hw.perflevel1.name") ?? "Efficiency"
    }

    func read() -> CPUSample {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return CPUSample() }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        // user, system, idle, nice ticks for every core
        var now: [[UInt32]] = []
        for i in 0..<Int(count) {
            let base = i * Int(CPU_STATE_MAX)
            now.append([
                UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]),
            ])
        }
        defer { previous = now }
        guard previous.count == now.count else {
            return CPUSample(cores: Array(repeating: 0, count: now.count))
        }

        var sample = CPUSample()
        var user = 0.0, system = 0.0, all = 0.0
        for (a, b) in zip(previous, now) {
            let u = Double(b[0] &- a[0]) + Double(b[3] &- a[3])
            let s = Double(b[1] &- a[1])
            let total = u + s + Double(b[2] &- a[2])
            sample.cores.append(total > 0 ? (u + s) / total : 0)
            user += u
            system += s
            all += total
        }
        if all > 0 {
            sample.user = user / all
            sample.system = system / all
            sample.total = (user + system) / all
        }
        return sample
    }
}
