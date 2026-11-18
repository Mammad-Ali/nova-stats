import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Prefs.shared
        prefs.applyDock()
        Monitor.shared.start()
        HUDController.shared.refresh()
        UNUserNotificationCenter.current().delegate = self
        if prefs.anyAlert { Alerts.shared.requestPermission() }
        if prefs.openOnLaunch || (!prefs.showMenuBar && !prefs.showHUD) {
            Windows.shared.showDashboard()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Windows.shared.showDashboard()
        return false
    }

    // novastats:// links, the widgets use them
    func application(_ application: NSApplication, open urls: [URL]) {
        Windows.shared.showDashboard()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // show alerts even while the app is in front
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { Windows.shared.showDashboard() }
        completionHandler()
    }
}
