import SwiftUI

// dark amber when cool, sun yellow when warm, red when hot
func heatColor(_ t: Double?) -> Color {
    guard let t else { return Color(white: 0.12) }
    let stops: [(Double, (Double, Double, Double))] = [
        (30, (0.24, 0.17, 0.02)),
        (55, (0.75, 0.55, 0.06)),
        (75, (1.0, 0.78, 0.1)),
        (95, (0.98, 0.44, 0.52)),
    ]
    if t <= stops[0].0 { return Color(red: stops[0].1.0, green: stops[0].1.1, blue: stops[0].1.2) }
    for i in 1..<stops.count where t <= stops[i].0 {
        let (t0, a) = stops[i - 1], (t1, b) = stops[i]
        let f = (t - t0) / (t1 - t0)
        return Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
    }
    let last = stops[stops.count - 1].1
    return Color(red: last.0, green: last.1, blue: last.2)
}

struct ChipMapCard: View {
    @Environment(Monitor.self) private var m

    var body: some View {
        let t = m.temps
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(icon: "cpu", title: "Chip heat map") {
                HeatScale()
            }
            ChipMap(performance: t.performanceCores, efficiency: t.efficiencyCores, gpu: t.gpuCores)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 0) {
                GroupTemp(label: "Performance", values: t.performanceCores)
                GroupTemp(label: "Efficiency", values: t.efficiencyCores)
                GroupTemp(label: "GPU", values: t.gpuCores)
            }
        }
        .card()
    }
}

struct GroupTemp: View {
    var label: String
    var values: [Double?]

    var body: some View {
        let live = values.compactMap { $0 }
        let avg = live.isEmpty ? nil : live.reduce(0, +) / Double(live.count)
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label) · \(values.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Nova.textLo)
            Text(formatTemp(avg))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(Nova.heat(avg))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Average of the \(values.count) \(label.lowercased()) sensors")
    }
}

struct HeatScale: View {
    var body: some View {
        HStack(spacing: 6) {
            Text(formatTemp(30))
            LinearGradient(colors: [30, 55, 75, 95].map { heatColor(Double($0)) }, startPoint: .leading, endPoint: .trailing)
                .frame(width: 70, height: 6)
                .clipShape(Capsule())
            Text(formatTemp(95))
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(Nova.textLo)
    }
}

// the chip seen from above at an angle, like the app icon. each tile is one
// of the chip's temperature sensors (apple doesn't say which core each sits on)
struct ChipMap: View {
    var performance: [Double?]
    var efficiency: [Double?]
    var gpu: [Double?]

    var body: some View {
        ZStack {
            // the chip's edge, so it looks like a slab rather than a sticker
            slab.brightness(-0.35).offset(y: 12)
            slab.brightness(-0.2).offset(y: 6)
            slab
            die
        }
        .frame(width: 230, height: 230)
        .rotationEffect(.degrees(45))
        .scaleEffect(x: 1, y: 0.56)
        .frame(width: 330, height: 200)
    }

    private var slab: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
    }

    private var die: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                cluster(performance, columns: 4)
                cluster(efficiency, columns: 2)
            }
            cluster(gpu, columns: 6)
        }
        .padding(22)
    }

    private func cluster(_ values: [Double?], columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
            ForEach(values.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(heatColor(values[i]))
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: heatColor(values[i]).opacity((values[i] ?? 0) > 60 ? 0.8 : 0), radius: 4)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Nova.sun.opacity(0.25), lineWidth: 1))
    }
}
