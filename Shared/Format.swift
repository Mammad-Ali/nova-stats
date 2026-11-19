import Foundation

// 3 significant digits, like Nova
func formatBytes(_ value: Double, base: Double = 1000) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var v = max(value, 0)
    var i = 0
    while v >= base * 0.999 && i < units.count - 1 {
        v /= base
        i += 1
    }
    let digits = i == 0 || v >= 100 ? 0 : (v >= 10 ? 1 : 2)
    return String(format: "%.\(digits)f %@", v, units[i])
}

func formatMemory(_ value: Double) -> String {
    formatBytes(value, base: 1024)
}

func formatRate(_ value: Double) -> String {
    formatBytes(value) + "/s"
}

// short form for the menu bar: 820K, 1.2M
func formatRateShort(_ value: Double) -> String {
    let units = ["B", "K", "M", "G"]
    var v = max(value, 0)
    var i = 0
    while v >= 999.5 && i < units.count - 1 {
        v /= 1000
        i += 1
    }
    return v < 10 && i > 0 ? String(format: "%.1f%@", v, units[i]) : String(format: "%.0f%@", v, units[i])
}

func formatPercent(_ value: Double) -> String {
    "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
}

// share of the whole cpu, one decimal while it's small
func formatShare(_ value: Double) -> String {
    let v = max(value, 0) * 100
    return v < 10 ? String(format: "%.1f%%", v) : String(format: "%.0f%%", v)
}

// sensors give celsius, this only changes how it's shown
enum TempUnit {
    static var fahrenheit = false
}

func formatTemp(_ value: Double?) -> String {
    guard let value else { return "—" }
    let shown = TempUnit.fahrenheit ? value * 9 / 5 + 32 : value
    return "\(Int(shown.rounded()))°"
}

func formatTempWithUnit(_ value: Double) -> String {
    formatTemp(value) + (TempUnit.fahrenheit ? "F" : "C")
}

func formatWatts(_ value: Double) -> String {
    if abs(value) < 0.05 { return "0 W" }
    return String(format: abs(value) < 10 ? "%.1f W" : "%.0f W", value)
}

func formatSession(_ seconds: TimeInterval) -> String {
    seconds < 60 ? "under a minute" : formatMinutes(Int(seconds / 60))
}

func formatMinutes(_ minutes: Int) -> String {
    minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
}

func formatUptime(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds) / 60
    let days = minutes / 1440, hours = minutes / 60 % 24, mins = minutes % 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(mins)m" }
    return "\(mins)m"
}
