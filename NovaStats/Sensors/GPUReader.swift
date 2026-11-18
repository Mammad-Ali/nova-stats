import Foundation

struct GPUSample {
    var usage = 0.0
    var memory = 0.0
}

final class GPUReader {
    let model: String
    let cores: Int

    init() {
        model = ioProperty("IOAccelerator", "model").first as? String ?? "GPU"
        cores = ioProperty("IOAccelerator", "gpu-core-count").first as? Int ?? 0
    }

    func read() -> GPUSample {
        var s = GPUSample()
        for case let stats as [String: Any] in ioProperty("IOAccelerator", "PerformanceStatistics") {
            if let usage = stats["Device Utilization %"] as? Int {
                s.usage = max(s.usage, Double(usage) / 100)
            }
            if let mem = stats["In use system memory"] as? Int {
                s.memory += Double(mem)
            }
        }
        return s
    }
}
