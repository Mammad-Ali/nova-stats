import Foundation

// what the app hands over to the widgets, about twice a minute
struct WidgetData: Codable {
    var date = Date()
    var chip = ""
    var cpu = 0.0
    var gpu = 0.0
    var memory = 0.0
    var memoryUsed = 0.0
    var memoryTotal = 0.0
    var pressure = 1
    var cpuTemp: Double?
    var gpuTemp: Double?
    var ssdTemp: Double?
    var diskFree = 0.0
    var diskTotal = 0.0
    var down = 0.0
    var up = 0.0
    var cpuHistory: [Double] = [] // last hour, a point a minute
    var topApp: String?
    var topAppCPU = 0.0

    static let sample = WidgetData(
        chip: "Apple M5", cpu: 0.23, gpu: 0.12, memory: 0.56, memoryUsed: 9.6e9, memoryTotal: 17.18e9,
        cpuTemp: 48, gpuTemp: 44, ssdTemp: 36, diskFree: 300e9, diskTotal: 494e9, down: 1.2e6, up: 84e3,
        cpuHistory: sampleHistory(),
        topApp: "Safari", topAppCPU: 0.06)

    private static func sampleHistory() -> [Double] {
        (0..<60).map { i -> Double in
            let wave = 0.08 * sin(Double(i) / 5)
            let spike: Double = i % 9 == 0 ? 0.25 : 0
            return 0.16 + wave + spike
        }
    }

    // the widget runs in its own sandbox, so the file sits under the real
    // home folder, the one folder the widget is allowed to read
    static var file: URL {
        var home = NSHomeDirectory()
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            home = String(cString: dir)
        }
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Nova Stats/widgets.json")
    }

    static func load() -> WidgetData? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetData.self, from: data)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.file, options: .atomic)
    }
}
