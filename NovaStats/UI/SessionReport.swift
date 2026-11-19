import SwiftUI

// the report that pops up when a game session ends
final class ReportWindow {
    static let shared = ReportWindow()

    private var window: NSWindow?

    func show(_ report: SessionReport) {
        let window = self.window ?? makeWindow()
        self.window = window
        let host = NSHostingView(rootView: ReportView(report: report) { [weak window] in window?.close() })
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Session report"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.level = .floating
        return window
    }
}

struct ReportView: View {
    var report: SessionReport
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Session report")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Nova.textLo)
                Text(report.game)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Nova.sun)
                    .lineLimit(1)
                Text("\(formatSession(report.duration)) · started \(report.start.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Nova.textMid)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: 3), spacing: 12) {
                ReportStat(label: "CPU", average: formatPercent(report.cpuAvg), peak: formatPercent(report.cpuPeak))
                ReportStat(label: "GPU", average: formatPercent(report.gpuAvg), peak: formatPercent(report.gpuPeak))
                ReportStat(label: "Power", average: report.powerAvg.map(formatWatts) ?? "—", peak: report.powerPeak.map(formatWatts) ?? "—")
                ReportStat(label: "CPU temperature", average: formatTemp(report.cpuTempAvg), peak: formatTemp(report.cpuTempPeak),
                           color: Nova.heat(report.cpuTempPeak))
                ReportStat(label: "GPU temperature", average: formatTemp(report.gpuTempAvg), peak: formatTemp(report.gpuTempPeak),
                           color: Nova.heat(report.gpuTempPeak))
                ReportStat(label: "Slowed by heat", average: report.hotSeconds > 0 ? formatSession(Double(report.hotSeconds)) : "Never",
                           peak: nil, color: report.hotSeconds > 0 ? Nova.amber : Nova.green)
            }

            if report.tempCurve.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CPU temperature during the session")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Nova.textMid)
                    LineChart(series: [Series(color: Nova.sun, values: report.tempCurve)], window: report.tempCurve.count,
                              maxValue: max((report.tempCurve.max() ?? 0) * 1.1, 50), grid: { formatTemp($0) })
                        .frame(height: 110)
                }
                .padding(14)
                .glass(16)
            }

            HStack {
                Text(report.hotSeconds > 0
                     ? "Your Mac got hot enough that macOS held it back for a while."
                     : "Your Mac stayed cool enough to run at full speed.")
                    .font(.system(size: 12))
                    .foregroundStyle(Nova.textLo)
                Spacer()
                Button("Close", action: close)
                    .buttonStyle(OutlineButton())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 540)
        .background(.black)
        .environment(\.colorScheme, .dark)
    }
}

struct ReportStat: View {
    var label: String
    var average: String
    var peak: String?
    var color: Color = Nova.textHi

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Nova.textLo)
            Text(average)
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(peak.map { "peak \($0)" } ?? " ")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Nova.textMid)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(14)
    }
}
