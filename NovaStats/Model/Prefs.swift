import AppKit
import Observation

enum Metric: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, cpuTemp, gpuTemp, ssdTemp, download, upload, diskFree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU load"
        case .gpu: "GPU load"
        case .memory: "Memory"
        case .cpuTemp: "CPU temp"
        case .gpuTemp: "GPU temp"
        case .ssdTemp: "SSD temp"
        case .download: "Download"
        case .upload: "Upload"
        case .diskFree: "Disk free"
        }
    }

    var short: String {
        switch self {
        case .cpu, .cpuTemp: "CPU"
        case .gpu, .gpuTemp: "GPU"
        case .memory: "RAM"
        case .ssdTemp: "SSD"
        case .diskFree: "DISK"
        case .download, .upload: ""
        }
    }

    var icon: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up"
        case .memory: "memorychip"
        case .cpuTemp, .gpuTemp, .ssdTemp: "thermometer.medium"
        case .download: "arrow.down"
        case .upload: "arrow.up"
        case .diskFree: "internaldrive"
        }
    }

    var isTemp: Bool { self == .cpuTemp || self == .gpuTemp || self == .ssdTemp }
}

enum Corner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}

enum HUDLayout: String, CaseIterable {
    case row, column

    var title: String { self == .row ? "Row" : "Column" }
}

@Observable
final class Prefs {
    static let shared = Prefs()

    @ObservationIgnored private let d = UserDefaults.standard

    var openOnLaunch: Bool { didSet { d.set(openOnLaunch, forKey: "openOnLaunch") } }
    var starfield: Bool { didSet { d.set(starfield, forKey: "starfield") } }
    var showDock: Bool {
        didSet {
            d.set(showDock, forKey: "showDock")
            applyDock()
        }
    }

    var showMenuBar: Bool {
        didSet {
            d.set(showMenuBar, forKey: "showMenuBar")
            // without both the app would be impossible to reach
            if !showMenuBar && !showDock { showDock = true }
        }
    }
    var menuBarItems: [Metric] { didSet { save(menuBarItems, "menuBarItems") } }

    var showHUD: Bool { didSet { d.set(showHUD, forKey: "showHUD"); HUDController.shared.refresh() } }
    var hudItems: [Metric] { didSet { save(hudItems, "hudItems"); HUDController.shared.refresh() } }
    var hudCorner: Corner { didSet { d.set(hudCorner.rawValue, forKey: "hudCorner"); HUDController.shared.refresh() } }
    var hudLayout: HUDLayout { didSet { d.set(hudLayout.rawValue, forKey: "hudLayout") } }
    var hudOpacity: Double { didSet { d.set(hudOpacity, forKey: "hudOpacity") } }

    var alertTemp: Bool { didSet { d.set(alertTemp, forKey: "alertTemp"); askForAlerts() } }
    var alertTempLimit: Double { didSet { d.set(alertTempLimit, forKey: "alertTempLimit") } }
    var alertMemory: Bool { didSet { d.set(alertMemory, forKey: "alertMemory"); askForAlerts() } }
    var alertDisk: Bool { didSet { d.set(alertDisk, forKey: "alertDisk"); askForAlerts() } }
    var alertDiskLimit: Double { didSet { d.set(alertDiskLimit, forKey: "alertDiskLimit") } }
    var alertCPU: Bool { didSet { d.set(alertCPU, forKey: "alertCPU"); askForAlerts() } }

    var anyAlert: Bool { alertTemp || alertMemory || alertDisk || alertCPU }

    init() {
        d.register(defaults: [
            "openOnLaunch": true,
            "starfield": true,
            "showDock": true,
            "showMenuBar": true,
            "menuBarItems": ["cpu", "cpuTemp"],
            "showHUD": false,
            "hudItems": ["cpu", "gpu", "memory", "cpuTemp"],
            "hudCorner": Corner.topRight.rawValue,
            "hudLayout": HUDLayout.row.rawValue,
            "hudOpacity": 0.75,
            "alertTemp": true,
            "alertTempLimit": 95.0,
            "alertMemory": true,
            "alertDisk": true,
            "alertDiskLimit": 10.0,
            "alertCPU": false,
        ])
        openOnLaunch = d.bool(forKey: "openOnLaunch")
        starfield = d.bool(forKey: "starfield")
        showDock = d.bool(forKey: "showDock")
        showMenuBar = d.bool(forKey: "showMenuBar")
        menuBarItems = Prefs.load(d, "menuBarItems")
        showHUD = d.bool(forKey: "showHUD")
        hudItems = Prefs.load(d, "hudItems")
        hudCorner = Corner(rawValue: d.string(forKey: "hudCorner") ?? "") ?? .topRight
        hudLayout = HUDLayout(rawValue: d.string(forKey: "hudLayout") ?? "") ?? .row
        hudOpacity = d.double(forKey: "hudOpacity")
        alertTemp = d.bool(forKey: "alertTemp")
        alertTempLimit = d.double(forKey: "alertTempLimit")
        alertMemory = d.bool(forKey: "alertMemory")
        alertDisk = d.bool(forKey: "alertDisk")
        alertDiskLimit = d.double(forKey: "alertDiskLimit")
        alertCPU = d.bool(forKey: "alertCPU")
    }

    func applyDock() {
        NSApp?.setActivationPolicy(showDock ? .regular : .accessory)
    }

    private func askForAlerts() {
        if anyAlert { Alerts.shared.requestPermission() }
    }

    private func save(_ items: [Metric], _ key: String) {
        d.set(items.map(\.rawValue), forKey: key)
    }

    private static func load(_ d: UserDefaults, _ key: String) -> [Metric] {
        (d.stringArray(forKey: key) ?? []).compactMap(Metric.init(rawValue:))
    }
}
