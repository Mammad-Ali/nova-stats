import SwiftUI
import ServiceManagement
import UserNotifications

enum SettingsSection: String, CaseIterable {
    case general, menuBar, hud, alerts

    var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu bar"
        case .hud: "HUD"
        case .alerts: "Alerts"
        }
    }
}

struct SettingsView: View {
    @State private var section = SettingsSection.general
    @State private var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Nova.heading)
            PillPicker(options: SettingsSection.allCases, label: \.title, selection: $section)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch section {
                    case .general: general
                    case .menuBar: menuBar
                    case .hud: hud
                    case .alerts: AlertSettings(prefs: prefs)
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
        .frame(width: 620, height: 600, alignment: .topLeading)
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
                LabeledRow(title: "Background") {
                    HStack(spacing: 10) {
                        Slider(value: $prefs.hudOpacity, in: 0.3...1)
                            .tint(Nova.sun)
                            .frame(width: 180)
                        Text(formatPercent(prefs.hudOpacity))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Nova.textMid)
                            .frame(width: 36, alignment: .trailing)
                    }
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
                SwitchRow(title: "Running hot", subtitle: "When the CPU stays above \(Int(prefs.alertTempLimit))° for 10 seconds.",
                          isOn: $prefs.alertTemp)
                if prefs.alertTemp {
                    SliderRow(value: $prefs.alertTempLimit, range: 70...105, step: 1, text: "\(Int(prefs.alertTempLimit))°")
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
