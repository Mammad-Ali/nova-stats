import Foundation
import UserNotifications

final class Alerts {
    static let shared = Alerts()

    private var lastSent: [String: Date] = [:]
    private var hotSince: Date?
    private var busySince: Date?
    private var asked = false

    func requestPermission() {
        guard !asked else { return }
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // runs on the main thread after every sample
    func check(_ m: Monitor) {
        let p = Prefs.shared
        let now = Date()

        if p.alertTemp, let t = m.temps.cpu, t >= p.alertTempLimit {
            hotSince = hotSince ?? now
            if now.timeIntervalSince(hotSince!) >= 10 {
                send("temp", "Your Mac is running hot", "The CPU is at \(Int(t.rounded()))°C.\(culprit(m))")
            }
        } else {
            hotSince = nil
        }

        if p.alertMemory, m.memory.pressure >= 2 {
            send("memory", "Memory is running low",
                 "Memory pressure is \(m.memory.pressure >= 4 ? "critical" : "high"). Closing some apps will help.")
        }

        if p.alertDisk, m.disk.total > 0, m.disk.free < p.alertDiskLimit * 1e9 {
            send("disk", "Disk is almost full", "Only \(formatBytes(m.disk.free)) left on \(m.disk.name).")
        }

        if p.alertCPU, m.cpu.total >= 0.9 {
            busySince = busySince ?? now
            if now.timeIntervalSince(busySince!) >= 60 {
                send("cpu", "CPU has been busy for a minute", "Load is \(formatPercent(m.cpu.total)).\(culprit(m))")
            }
        } else {
            busySince = nil
        }
    }

    func sendTest() {
        requestPermission()
        post("Nova Stats alerts are on", "This is what an alert looks like.")
    }

    private func culprit(_ m: Monitor) -> String {
        guard let top = m.topCPU.first, top.cpu > 0.05 else { return "" }
        return " \(top.name) is using the most CPU."
    }

    // one of each kind per half hour at most
    private func send(_ kind: String, _ title: String, _ body: String) {
        if let last = lastSent[kind], Date().timeIntervalSince(last) < 1800 { return }
        lastSent[kind] = Date()
        post(title, body)
    }

    private func post(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
