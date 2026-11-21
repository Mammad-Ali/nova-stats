import SwiftUI

// 270° arc like Nova's speedometer
struct Ring<Center: View>: View {
    var value: Double
    var color: Color = Nova.sun
    var width: CGFloat = 10
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            arc(0.75).stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: width, lineCap: .round))
            arc(0.75 * min(max(value, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            center
        }
        .padding(width / 2)
    }

    private func arc(_ to: Double) -> some Shape {
        Circle().trim(from: 0, to: to).rotation(.degrees(135))
    }
}

struct Series {
    var color: Color
    var values: [Double]
}

// right-aligned line chart, newest sample on the right
struct LineChart: View {
    var series: [Series]
    var window = 60
    var maxValue: Double? = nil
    var grid: ((Double) -> String)? = nil

    var body: some View {
        GeometryReader { geo in
            let top = scale
            ZStack(alignment: .topLeading) {
                if let grid {
                    ForEach(0..<3, id: \.self) { i in
                        let y = geo.size.height * CGFloat(i) / 2
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(.white.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: i == 2 ? [] : [3, 4]))
                        Text(grid(top * Double(2 - i) / 2))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(Nova.textLo)
                            .offset(x: 4, y: i == 2 ? y - 15 : y + 3)
                    }
                }
                ForEach(series.indices, id: \.self) { i in
                    let s = series[i]
                    area(s.values, top, geo.size)
                        .fill(LinearGradient(colors: [s.color.opacity(0.22), s.color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    line(s.values, top, geo.size)
                        .stroke(s.color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private var scale: Double {
        if let maxValue { return maxValue }
        let peak = series.flatMap { $0.values.suffix(window) }.max() ?? 0
        return max(peak * 1.15, 1)
    }

    private func points(_ values: [Double], _ top: Double, _ size: CGSize) -> [CGPoint] {
        let tail = values.suffix(window)
        let step = size.width / CGFloat(max(window - 1, 1))
        let start = CGFloat(window - tail.count) * step
        return tail.enumerated().map { i, v in
            CGPoint(x: start + CGFloat(i) * step, y: size.height * (1 - CGFloat(min(max(v / top, 0), 1))))
        }
    }

    private func line(_ values: [Double], _ top: Double, _ size: CGSize) -> Path {
        Path { p in
            let pts = points(values, top, size)
            guard let first = pts.first else { return }
            p.move(to: first)
            pts.dropFirst().forEach { p.addLine(to: $0) }
        }
    }

    private func area(_ values: [Double], _ top: Double, _ size: CGSize) -> Path {
        Path { p in
            let pts = points(values, top, size)
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: size.height))
            pts.forEach { p.addLine(to: $0) }
            p.addLine(to: CGPoint(x: last.x, y: size.height))
            p.closeSubpath()
        }
    }
}

struct Chip: View {
    var text: String
    var color: Color = Nova.textMid

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
    }
}

struct CardHeader<Trailing: View>: View {
    var icon: String
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Nova.textMid)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Nova.textHi)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(icon: String, title: String) {
        self.init(icon: icon, title: title) { EmptyView() }
    }
}

struct Stat: View {
    var label: String
    var value: String
    var color: Color = Nova.textHi

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Nova.textLo)
            Text(value)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct Meter: View {
    var value: Double
    var color: Color = Nova.sun
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule().fill(color)
                    .frame(width: max(geo.size.width * min(max(value, 0), 1), value > 0 ? height : 0))
            }
        }
        .frame(height: height)
    }
}

struct Legend: View {
    var color: Color
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Nova.textMid)
        }
    }
}

// white pill that slides between options, same as the tab bar
struct PillPicker<T: Hashable>: View {
    var options: [T]
    var label: (T) -> String
    @Binding var selection: T
    var small = false
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let active = option == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(size: small ? 11 : 13, weight: .semibold))
                        .foregroundStyle(active ? Color.black : Nova.textMid)
                        .lineLimit(1)
                        .fixedSize(horizontal: small, vertical: false) // small pickers never cut their labels
                        .padding(.horizontal, small ? 10 : 12)
                        .frame(maxWidth: small ? nil : .infinity)
                        .frame(height: small ? 22 : 32)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: small ? 7 : 10, style: .continuous)
                                    .fill(.white)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(small ? 3 : 4)
        .background(RoundedRectangle(cornerRadius: small ? 10 : 14, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: small ? 10 : 14, style: .continuous).strokeBorder(.white.opacity(0.10)))
    }
}

// Nova's choice chip: white with black text when picked
struct ChoiceChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.white : Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(selected ? 0 : 0.14)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Flow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.items.isEmpty {
                rows.append(current)
                current = ([i], size.width, size.height)
            } else {
                current = (current.items + [i], needed, max(current.height, size.height))
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

// averages long history down to about 300 points so an hour still draws fast
func downsample(_ values: [Double], seconds: Int, points: Int = 300) -> [Double] {
    let tail = Array(values.suffix(seconds))
    let bucket = max(seconds / points, 1)
    guard bucket > 1 else { return tail }
    var out: [Double] = []
    var end = tail.count
    while end > 0 {
        let start = max(end - bucket, 0)
        let slice = tail[start..<end]
        out.append(slice.reduce(0, +) / Double(slice.count))
        end = start
    }
    return out.reversed()
}
