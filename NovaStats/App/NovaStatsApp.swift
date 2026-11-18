import SwiftUI

@main
struct NovaStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var monitor = Monitor.shared
    @State private var prefs = Prefs.shared

    var body: some Scene {
        MenuBarExtra(isInserted: $prefs.showMenuBar) {
            MenuPanel()
                .environment(monitor)
        } label: {
            MenuBarLabel(monitor: monitor, prefs: prefs)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { Windows.shared.showSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button("Dashboard") { Windows.shared.showDashboard() }
                    .keyboardShortcut("0")
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w")
            }
        }
    }
}
