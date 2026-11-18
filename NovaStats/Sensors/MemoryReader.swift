import Foundation

struct MemorySample {
    var total = 0.0
    var used = 0.0
    var app = 0.0
    var wired = 0.0
    var compressed = 0.0
    var cached = 0.0
    var swap = 0.0
    var pressure = 1 // 1 normal, 2 warning, 4 critical

    var fraction: Double { total > 0 ? used / total : 0 }
}

final class MemoryReader {
    func read() -> MemorySample {
        var s = MemorySample()
        s.total = Double(ProcessInfo.processInfo.physicalMemory)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return s }

        // same math Activity Monitor uses
        let page = Double(vm_kernel_page_size)
        s.app = (Double(stats.internal_page_count) - Double(stats.purgeable_count)) * page
        s.wired = Double(stats.wire_count) * page
        s.compressed = Double(stats.compressor_page_count) * page
        s.cached = (Double(stats.external_page_count) + Double(stats.purgeable_count)) * page
        s.used = s.app + s.wired + s.compressed

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            s.swap = Double(swap.xsu_used)
        }
        s.pressure = sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1
        return s
    }
}
