import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let data: WidgetData
    let fresh: Bool // false when the app hasn't written for a while
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, data: .sample, fresh: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(entry())
    }

    // the app asks for a reload every few minutes while it runs
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(300))))
    }

    private func entry() -> Entry {
        guard let data = WidgetData.load() else { return Entry(date: .now, data: .sample, fresh: false) }
        return Entry(date: .now, data: data, fresh: Date().timeIntervalSince(data.date) < 600)
    }
}

// black with a few faint stars, like Nova
struct WidgetSky: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 3
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(1 << 53)
            }
            for _ in 0..<Int(size.width * size.height / 900) {
                let r = next() < 0.1 ? 1.1 : 0.6
                ctx.fill(Path(ellipseIn: CGRect(x: next() * size.width, y: next() * size.height, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.15 + next() * 0.4)))
            }
        }
        .background(.black)
    }
}

struct WidgetRing: View {
    var value: Double
    var size: CGFloat
    var width: CGFloat
    var font: CGFloat

    var body: some View {
        Ring(value: value, width: width) {
            Text(formatPercent(value))
                .font(.system(size: font, weight: .semibold).monospacedDigit())
                .foregroundStyle(Nova.textHi)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
    }
}

struct Label2: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Nova.textMid)
    }
}

struct Waiting: View {
    var body: some View {
        Text("Open Nova Stats to see live numbers")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Nova.textLo)
            .multilineTextAlignment(.center)
    }
}

// MARK: small

struct CPUView: View {
    var entry: Entry

    var body: some View {
        let d = entry.data
        VStack(spacing: 6) {
            HStack {
                Label2(icon: "cpu", title: "CPU")
                Spacer()
                Text(formatTemp(d.cpuTemp))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Nova.heat(d.cpuTemp))
            }
            Spacer(minLength: 0)
            if entry.fresh {
                WidgetRing(value: d.cpu, size: 96, width: 9, font: 24)
            } else {
                Waiting()
            }
            Spacer(minLength: 0)
            Text(d.topApp.map { "\($0) \(formatShare(d.topAppCPU))" } ?? d.chip)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Nova.textLo)
                .lineLimit(1)
        }
        .widgetURL(URL(string: "novastats://dashboard"))
    }
}

struct MemoryView: View {
    var entry: Entry

    var body: some View {
        let d = entry.data
        VStack(spacing: 6) {
            HStack {
                Label2(icon: "memorychip", title: "Memory")
                Spacer()
                Circle()
                    .fill(d.pressure >= 4 ? Nova.red : d.pressure >= 2 ? Nova.amber : Nova.green)
                    .frame(width: 7, height: 7)
            }
            Spacer(minLength: 0)
            if entry.fresh {
                WidgetRing(value: d.memory, size: 96, width: 9, font: 24)
            } else {
                Waiting()
            }
            Spacer(minLength: 0)
            Text("\(formatMemory(d.memoryUsed)) of \(formatMemory(d.memoryTotal))")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Nova.textLo)
                .lineLimit(1)
        }
        .widgetURL(URL(string: "novastats://dashboard"))
    }
}

// MARK: medium

struct RingColumn: View {
    var title: String
    var value: Double
    var temp: Double?
    var size: CGFloat = 70

    var body: some View {
        VStack(spacing: 6) {
            WidgetRing(value: value, size: size, width: 7, font: 17)
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Nova.textMid)
                if let temp {
                    Text(formatTemp(temp))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Nova.heat(temp))
                }
            }
        }
    }
}

struct InfoRow: View {
    var icon: String
    var color: Color
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(color)
                .frame(width: 12)
            Text(text)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Nova.textHi)
                .lineLimit(1)
        }
    }
}

struct SystemView: View {
    var entry: Entry

    var body: some View {
        let d = entry.data
        if entry.fresh {
            HStack(spacing: 12) {
                RingColumn(title: "CPU", value: d.cpu, temp: d.cpuTemp, size: 64)
                RingColumn(title: "GPU", value: d.gpu, temp: d.gpuTemp, size: 64)
                RingColumn(title: "RAM", value: d.memory, temp: nil, size: 64)
                VStack(alignment: .leading, spacing: 9) {
                    InfoRow(icon: "arrow.down", color: Nova.down, text: formatRate(d.down))
                    InfoRow(icon: "arrow.up", color: Nova.up, text: formatRate(d.up))
                    InfoRow(icon: "internaldrive", color: Nova.textLo, text: formatBytes(d.diskFree))
                    InfoRow(icon: "thermometer.medium", color: Nova.textLo, text: "SSD \(formatTemp(d.ssdTemp))")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .widgetURL(URL(string: "novastats://dashboard"))
        } else {
            Waiting()
        }
    }
}

// MARK: large

struct DashboardWidgetView: View {
    var entry: Entry

    var body: some View {
        let d = entry.data
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nova Stats")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Nova.heading)
                Spacer()
                Text(entry.fresh ? "\(d.chip) · \(d.date.formatted(date: .omitted, time: .shortened))" : "Not running")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Nova.textLo)
            }
            HStack {
                RingColumn(title: "CPU", value: d.cpu, temp: d.cpuTemp, size: 78)
                Spacer()
                RingColumn(title: "GPU", value: d.gpu, temp: d.gpuTemp, size: 78)
                Spacer()
                RingColumn(title: "RAM", value: d.memory, temp: nil, size: 78)
            }
            .padding(.horizontal, 8)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CPU, last hour")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Nova.textMid)
                    Spacer()
                    if let app = d.topApp {
                        Text("Top: \(app)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Nova.textLo)
                            .lineLimit(1)
                    }
                }
                LineChart(series: [Series(color: Nova.sun, values: d.cpuHistory)], window: 60, maxValue: 1)
                    .frame(maxHeight: .infinity)
            }
            .padding(12)
            .glass(14)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    InfoRow(icon: "arrow.down", color: Nova.down, text: formatRate(d.down))
                    InfoRow(icon: "arrow.up", color: Nova.up, text: formatRate(d.up))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    InfoRow(icon: "internaldrive", color: Nova.textLo, text: "\(formatBytes(d.diskFree)) free")
                    Meter(value: d.diskTotal > 0 ? 1 - d.diskFree / d.diskTotal : 0, height: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "novastats://dashboard"))
    }
}

// MARK: widgets

struct CPUWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "cpu", provider: Provider()) { entry in
            CPUView(entry: entry).containerBackground(for: .widget) { WidgetSky() }
        }
        .configurationDisplayName("CPU")
        .description("CPU load, temperature and the busiest app.")
        .supportedFamilies([.systemSmall])
    }
}

struct MemoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "memory", provider: Provider()) { entry in
            MemoryView(entry: entry).containerBackground(for: .widget) { WidgetSky() }
        }
        .configurationDisplayName("Memory")
        .description("How much memory is in use.")
        .supportedFamilies([.systemSmall])
    }
}

struct SystemWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "system", provider: Provider()) { entry in
            SystemView(entry: entry).containerBackground(for: .widget) { WidgetSky() }
        }
        .configurationDisplayName("System")
        .description("CPU, GPU, memory, network and disk at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

struct DashboardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dashboard", provider: Provider()) { entry in
            DashboardWidgetView(entry: entry).containerBackground(for: .widget) { WidgetSky() }
        }
        .configurationDisplayName("Dashboard")
        .description("Everything, plus the last hour of CPU.")
        .supportedFamilies([.systemLarge])
    }
}

@main
struct NovaStatsWidgets: WidgetBundle {
    var body: some Widget {
        CPUWidget()
        MemoryWidget()
        SystemWidget()
        DashboardWidget()
    }
}
