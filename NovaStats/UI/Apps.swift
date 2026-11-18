import SwiftUI

enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(_ path: String) -> NSImage {
        if let known = cache[path] { return known }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}

enum AppSort: String, CaseIterable {
    case memory, cpu

    var title: String { self == .memory ? "Memory" : "CPU" }
}

// the busiest apps, by memory or by cpu
struct AppsCard: View {
    @Environment(Monitor.self) private var m
    @AppStorage("appSort") private var sort = AppSort.memory

    var body: some View {
        let apps = sort == .memory ? m.topMemory : m.topCPU
        let top = sort == .memory ? max(m.topMemory.first?.memory ?? 0, 1) : max(m.topCPU.first?.cpu ?? 0, 0.01)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardHeader(icon: "list.bullet.rectangle", title: "Apps")
                PillPicker(options: AppSort.allCases, label: \.title, selection: $sort, small: true)
            }
            if apps.isEmpty {
                Text("Measuring…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Nova.textLo)
            }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(apps) { app in
                        HStack(spacing: 10) {
                            AppIconView(path: app.path)
                            VStack(spacing: 5) {
                                HStack {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Nova.textHi)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(sort == .memory ? formatMemory(app.memory) : formatShare(app.cpu))
                                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(Nova.textHi)
                                }
                                Meter(value: (sort == .memory ? app.memory : app.cpu) / top, height: 3)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .card()
    }
}

struct AppIconView: View {
    var path: String?

    var body: some View {
        Group {
            if let path {
                Image(nsImage: AppIcons.icon(path))
                    .resizable()
            } else {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Nova.textLo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.06)))
            }
        }
        .frame(width: 24, height: 24)
    }
}
