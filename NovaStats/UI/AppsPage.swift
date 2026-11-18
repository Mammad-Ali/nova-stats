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

struct AppsPage: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        HStack(spacing: 16) {
            AppList(icon: "cpu", title: "Using the most CPU", apps: m.topCPU,
                    value: { formatShare($0.cpu) },
                    fraction: { $0.cpu / max(m.topCPU.first?.cpu ?? 0, 0.01) })
            AppList(icon: "memorychip", title: "Using the most memory", apps: m.topMemory,
                    value: { formatMemory($0.memory) },
                    fraction: { $0.memory / max(m.topMemory.first?.memory ?? 0, 1) })
        }
    }
}

struct AppList: View {
    var icon: String
    var title: String
    var apps: [AppUsage]
    var value: (AppUsage) -> String
    var fraction: (AppUsage) -> Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeader(icon: icon, title: title)
            if apps.isEmpty {
                Text("Measuring…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Nova.textLo)
            }
            ForEach(apps) { app in
                HStack(spacing: 12) {
                    AppIconView(path: app.path)
                    VStack(spacing: 6) {
                        HStack {
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Nova.textHi)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(value(app))
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Nova.textHi)
                        }
                        Meter(value: fraction(app), height: 4)
                    }
                }
            }
            Spacer(minLength: 0)
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
        .frame(width: 26, height: 26)
    }
}
