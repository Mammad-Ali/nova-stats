import SwiftUI

// the dashboard and settings are plain AppKit windows so they can be opened
// from anywhere (menu bar, dock, notifications) and torn down when closed
final class Windows: NSObject, NSWindowDelegate {
    static let shared = Windows()

    private var dashboard: NSWindow?
    private var settings: NSWindow?

    func showDashboard() {
        let window = dashboard ?? makeWindow(size: NSSize(width: 1140, height: 780), resizable: true, name: "Dashboard")
        window.minSize = NSSize(width: 1000, height: 700)
        dashboard = window
        if !(window.contentView is NSHostingView<AnyView>) {
            window.contentView = NSHostingView(rootView: AnyView(DashboardView().environment(Monitor.shared)))
        }
        show(window)
    }

    // the shortcut opens the dashboard, or puts it away if it's already in front
    func toggleDashboard() {
        if let dashboard, dashboard.isVisible, dashboard.isKeyWindow, NSApp.isActive {
            dashboard.performClose(nil)
        } else {
            showDashboard()
        }
    }

    func showSettings(_ section: SettingsSection? = nil) {
        let window = settings ?? makeWindow(size: NSSize(width: 620, height: 620), resizable: false, name: "Settings")
        settings = window
        if section != nil || !(window.contentView is NSHostingView<AnyView>) {
            window.contentView = NSHostingView(rootView: AnyView(SettingsView(section: section ?? .general).environment(Monitor.shared)))
        }
        show(window)
    }

    private func show(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(size: NSSize, resizable: Bool, name: String) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = name == "Dashboard" ? "Nova Stats" : name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false // we decide what opens at launch, not macOS's resume
        window.delegate = self
        window.center()
        window.setFrameAutosaveName(name)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        // drop the swiftui tree, a closed window shouldn't keep drawing stars
        DispatchQueue.main.async { window.contentView = NSView() }
    }
}
