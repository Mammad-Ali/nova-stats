import SwiftUI
import ServiceManagement
import UserNotifications

enum SettingsSection: String, CaseIterable {
    case general, menuBar, hud, alerts, about

    var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu bar"
        case .hud: "HUD"
        case .alerts: "Alerts"
        case .about: "About"
        }
    }
}

struct SettingsView: View {
    @State var section: SettingsSection
    @State private var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Nova.sun)
            PillPicker(options: SettingsSection.allCases, label: \.title, selection: $section)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch section {
                    case .general: general
                    case .menuBar: menuBar
                    case .hud: hud
                    case .alerts: AlertSettings(prefs: prefs)
                    case .about: AboutSection()
                    }
                }
                .padding(.bottom, 24)
                .id(section)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .frame(width: 620, height: 620, alignment: .topLeading)
        .background(.black)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var general: some View {
        Group {
            SectionTitle("Dashboard")
            Rows {
                SwitchRow(title: "Open the dashboard at launch", isOn: $prefs.openOnLaunch)
                SwitchRow(title: "Moving stars", subtitle: "Nova's 3D starfield behind the dashboard. Off saves a bit of battery.",
                          isOn: $prefs.starfield)
            }
            SectionTitle("Units")
            Rows {
                LabeledRow(title: "Temperature") {
                    PillPicker(options: [false, true], label: { $0 ? "°F" : "°C" }, selection: $prefs.fahrenheit, small: true)
                }
            }
            SectionTitle("Shortcuts")
            Rows {
                LabeledRow(title: "Open or close the dashboard") {
                    ShortcutField(shortcut: $prefs.dashboardShortcut)
                }
                LabeledRow(title: "Show or hide the HUD") {
                    ShortcutField(shortcut: $prefs.hudShortcut)
                }
            }
            SectionTitle("App")
            Rows {
                SwitchRow(title: "Show in Dock",
                          subtitle: prefs.showMenuBar ? nil : "Stays on while the menu bar item is off, so you can reach the app.",
                          isOn: $prefs.showDock)
                    .disabled(!prefs.showMenuBar)
                LoginRow()
            }
        }
    }

    @ViewBuilder private var menuBar: some View {
        Group {
            Rows {
                SwitchRow(title: "Show in menu bar", subtitle: "Live numbers next to the clock. Click them for a quick panel.",
                          isOn: $prefs.showMenuBar)
                SwitchRow(title: "CPU graph", subtitle: "A tiny live chart of the last 12 seconds before the numbers.",
                          isOn: $prefs.menuBarGraph)
            }
            SectionTitle("Shows")
            MetricPicker(selection: $prefs.menuBarItems)
            SectionTitle("Preview")
            HStack {
                Spacer()
                MenuBarLabel(monitor: Monitor.shared, prefs: prefs)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.1)))
                Spacer()
            }
            .padding(.vertical, 14)
            .glass(16)
        }
    }

    @ViewBuilder private var hud: some View {
        Group {
            Rows {
                SwitchRow(title: "Show HUD", subtitle: "A small box with live stats on top of every app. Clicks go right through it.",
                          isOn: $prefs.showHUD)
            }
            SectionTitle("Position")
            Rows {
                LabeledRow(title: "Corner") {
                    PillPicker(options: Corner.allCases, label: \.title, selection: $prefs.hudCorner, small: true)
                }
                LabeledRow(title: "Layout") {
                    PillPicker(options: HUDLayout.allCases, label: \.title, selection: $prefs.hudLayout, small: true)
                }
            }
            SectionTitle("Shows")
            MetricPicker(selection: $prefs.hudItems)
        }
    }
}

struct AlertSettings: View {
    @Bindable var prefs: Prefs
    @State private var denied = false

    var body: some View {
        Group {
            if denied {
                HStack {
                    Text("Notifications for Nova Stats are turned off in System Settings.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Nova.amber)
                    Spacer()
                    Button("Open") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                    .buttonStyle(OutlineButton())
                }
                .padding(14)
                .glass(16)
            }
            Rows {
                SwitchRow(title: "Running hot", subtitle: "When the CPU stays above \(formatTemp(prefs.alertTempLimit)) for 10 seconds.",
                          isOn: $prefs.alertTemp)
                if prefs.alertTemp {
                    SliderRow(value: $prefs.alertTempLimit, range: 70...105, step: 1, text: formatTemp(prefs.alertTempLimit))
                }
                SwitchRow(title: "Low memory", subtitle: "When macOS says memory pressure is high.", isOn: $prefs.alertMemory)
                SwitchRow(title: "Disk almost full", subtitle: "When less than \(Int(prefs.alertDiskLimit)) GB is free.",
                          isOn: $prefs.alertDisk)
                if prefs.alertDisk {
                    SliderRow(value: $prefs.alertDiskLimit, range: 5...100, step: 5, text: "\(Int(prefs.alertDiskLimit)) GB")
                }
                SwitchRow(title: "Busy CPU", subtitle: "When the load stays above 90% for a whole minute.", isOn: $prefs.alertCPU)
            }
            HStack {
                Text("You get each alert at most once every 30 minutes.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Nova.textLo)
                Spacer()
                Button("Send a test alert") { Alerts.shared.sendTest() }
                    .buttonStyle(OutlineButton())
            }
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            denied = settings.authorizationStatus == .denied
        }
    }
}

struct LoginRow: View {
    @State private var on = SMAppService.mainApp.status == .enabled

    var body: some View {
        SwitchRow(title: "Open at login", isOn: Binding(get: { on }, set: { value in
            do {
                if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {}
            on = SMAppService.mainApp.status == .enabled
        }))
    }
}

struct MetricPicker: View {
    @Binding var selection: [Metric]

    var body: some View {
        Flow(spacing: 8) {
            ForEach(Metric.allCases) { metric in
                ChoiceChip(title: metric.title, selected: selection.contains(metric)) {
                    var picked = Set(selection)
                    if picked.contains(metric) { picked.remove(metric) } else { picked.insert(metric) }
                    selection = Metric.allCases.filter(picked.contains)
                }
            }
        }
    }
}

struct SectionTitle: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(Nova.textMid)
            .padding(.bottom, -10)
    }
}

struct Rows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(16)
    }
}

struct SwitchRow: View {
    var title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Nova.textLo)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color(hex: 0x9333EA))
        }
    }
}

struct LabeledRow<Control: View>: View {
    var title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            control
        }
    }
}

struct SliderRow: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var text: String

    var body: some View {
        HStack(spacing: 12) {
            Slider(value: $value, in: range, step: step)
                .tint(Nova.sun)
            Text(text)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Nova.textHi)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.top, -6)
    }
}

// click, then type the new key combo. esc cancels
struct ShortcutField: View {
    @Binding var shortcut: Shortcut?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type a shortcut…" : shortcut?.label ?? "Off")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(recording ? Color.black : .white)
                    .frame(minWidth: 96)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(recording ? Color.white : .white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(recording ? 0 : 0.14)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click and press the keys you want")

            if shortcut != nil && !recording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Nova.textLo)
                }
                .buttonStyle(.plain)
                .help("Turn this shortcut off")
            }
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        recording = true
        Hotkeys.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // esc
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // needs at least one of control, option, command, or it would swallow normal typing
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
            shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: Hotkeys.carbon(flags),
                                label: Hotkeys.label(flags, event))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        Hotkeys.shared.register()
    }
}

struct AboutSection: View {
    @State private var open: Int?

    var body: some View {
        Group {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nova Stats")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Nova.sun)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · MIT license")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Nova.textMid)
                    Text("Made by Ali Mammadli")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Nova.textLo)
                }
                Spacer()
            }
            Text(Help.about)
                .font(.system(size: 13))
                .foregroundStyle(Nova.textMid)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Website") { NSWorkspace.shared.open(Help.website) }
                    .buttonStyle(OutlineButton())
                Button("Source code") { NSWorkspace.shared.open(Help.source) }
                    .buttonStyle(OutlineButton())
                Button("License") { NSWorkspace.shared.open(Help.license) }
                    .buttonStyle(OutlineButton())
                Button("Report a problem") { NSWorkspace.shared.open(Help.issues) }
                    .buttonStyle(OutlineButton())
            }
            SectionTitle("Questions")
            VStack(spacing: 0) {
                ForEach(Help.questions.indices, id: \.self) { i in
                    Question(title: Help.questions[i].0, answer: Help.questions[i].1, open: open == i) {
                        withAnimation(.easeOut(duration: 0.2)) { open = open == i ? nil : i }
                    }
                    if i < Help.questions.count - 1 {
                        Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .glass(16)
        }
    }
}

struct Question: View {
    var title: String
    var answer: String
    var open: Bool
    var toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Nova.textLo)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                Text(answer)
                    .font(.system(size: 13))
                    .foregroundStyle(Nova.textMid)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 13)
    }
}
