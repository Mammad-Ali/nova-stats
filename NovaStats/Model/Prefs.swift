import AppKit
import Observation

enum Metric: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, cpuTemp, gpuTemp, ssdTemp, download, upload, diskFree, battery, power

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
        case .battery: "Battery"
        case .power: "Power"
        }
    }

    var short: String {
        switch self {
        case .cpu, .cpuTemp: "CPU"
        case .gpu, .gpuTemp: "GPU"
        case .memory: "RAM"
        case .ssdTemp: "SSD"
        case .diskFree: "DISK"
        case .battery: "BAT"
        case .power: "PWR"
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
        case .battery: "battery.75percent"
        case .power: "bolt.fill"
        }
    }

    var isTemp: Bool { self == .cpuTemp || self == .gpuTemp || self == .ssdTemp }
}

// a global key combo, in the carbon form RegisterEventHotKey wants
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    static let dashboard = Shortcut(keyCode: 45, modifiers: 4096 | 2048, label: "⌃⌥N") // control option N
    static let hud = Shortcut(keyCode: 4, modifiers: 4096 | 2048, label: "⌃⌥H")
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
    var menuBarGraph: Bool { didSet { d.set(menuBarGraph, forKey: "menuBarGraph") } }

    var fahrenheit: Bool {
        didSet {
            d.set(fahrenheit, forKey: "fahrenheit")
            TempUnit.fahrenheit = fahrenheit
        }
    }

    var dashboardShortcut: Shortcut? { didSet { saveShortcut(dashboardShortcut, "dashboardShortcut") } }
    var hudShortcut: Shortcut? { didSet { saveShortcut(hudShortcut, "hudShortcut") } }

    var showHUD: Bool { didSet { d.set(showHUD, forKey: "showHUD"); HUDController.shared.refresh() } }
    var hudItems: [Metric] { didSet { save(hudItems, "hudItems"); HUDController.shared.refresh() } }
    var hudCorner: Corner { didSet { d.set(hudCorner.rawValue, forKey: "hudCorner"); HUDController.shared.refresh() } }
    var hudLayout: HUDLayout { didSet { d.set(hudLayout.rawValue, forKey: "hudLayout") } }

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
            "menuBarGraph": false,
            "fahrenheit": false,
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
        menuBarGraph = d.bool(forKey: "menuBarGraph")
        fahrenheit = d.bool(forKey: "fahrenheit")
        dashboardShortcut = Prefs.loadShortcut(d, "dashboardShortcut", .dashboard)
        hudShortcut = Prefs.loadShortcut(d, "hudShortcut", .hud)
        alertTemp = d.bool(forKey: "alertTemp")
        alertTempLimit = d.double(forKey: "alertTempLimit")
        alertMemory = d.bool(forKey: "alertMemory")
        alertDisk = d.bool(forKey: "alertDisk")
        alertDiskLimit = d.double(forKey: "alertDiskLimit")
        alertCPU = d.bool(forKey: "alertCPU")
        TempUnit.fahrenheit = fahrenheit
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

    // nothing stored means the default, an empty value means switched off
    private func saveShortcut(_ shortcut: Shortcut?, _ key: String) {
        d.set(shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: key)
        Hotkeys.shared.register()
    }

    private static func loadShortcut(_ d: UserDefaults, _ key: String, _ fallback: Shortcut) -> Shortcut? {
        guard let data = d.data(forKey: key) else { return fallback }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    private static func load(_ d: UserDefaults, _ key: String) -> [Metric] {
        (d.stringArray(forKey: key) ?? []).compactMap(Metric.init(rawValue:))
    }
}
