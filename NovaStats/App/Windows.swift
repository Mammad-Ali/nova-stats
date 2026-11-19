import SwiftUI

// the dashboard is a plain AppKit window so it can be opened from anywhere
// (menu bar, dock, shortcuts, widgets) and torn down when closed.
// settings live inside it as a panel, not in a window of their own
final class Windows: NSObject, NSWindowDelegate {
    static let shared = Windows()

    private var dashboard: NSWindow?

    // open, not covered and not minimized: the sampler only works hard then
    var dashboardOnScreen: Bool {
        guard let dashboard, dashboard.isVisible, !dashboard.isMiniaturized else { return false }
        return dashboard.occlusionState.contains(.visible) && dashboard.contentView is NSHostingView<AnyView>
    }

    func showDashboard() {
        let window = dashboard ?? makeWindow()
        dashboard = window
        if !(window.contentView is NSHostingView<AnyView>) {
            window.contentView = NSHostingView(rootView: AnyView(DashboardView().environment(Monitor.shared)))
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    // the shortcut opens the dashboard, or puts it away if it's already in front
    func toggleDashboard() {
        if let dashboard, dashboard.isVisible, dashboard.isKeyWindow, NSApp.isActive {
            dashboard.performClose(nil)
        } else {
            showDashboard()
        }
    }

    func showSettings(_ section: SettingsSection = .general) {
        showDashboard()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            UIState.shared.settings = section
        }
    }

    func toggleSettings() {
        if UIState.shared.settings != nil, dashboard?.isKeyWindow == true {
            closeSettings()
        } else {
            showSettings()
        }
    }

    func closeSettings() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
            UIState.shared.settings = nil
        }
    }

    private func makeWindow() -> NSWindow {
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 780), styleMask: style, backing: .buffered, defer: false)
        window.title = "Nova Stats"
        window.minSize = NSSize(width: 1000, height: 700)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false // we decide what opens at launch, not macOS's resume
        window.tabbingMode = .disallowed // never merge into a tab, even in full screen
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("Dashboard")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        UIState.shared.settings = nil
        // drop the swiftui tree, a closed window shouldn't keep drawing stars
        DispatchQueue.main.async { window.contentView = NSView() }
    }
}
