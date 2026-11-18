// draws the app icon (the 3d chip with gold pins): swiftc tool/make_icon.swift -o make_icon && ./make_icon out.png
import SwiftUI

let sun = Color(red: 1, green: 0.776, blue: 0.102)

struct Sparkle: Shape {
    // nova's star: four long points, four short ones between them
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let long = rect.width / 2, short = long * 0.42, inner = long * 0.17
        var p = Path()
        for i in 0..<16 {
            let angle = Double(i) * .pi / 8 - .pi / 2
            let r = i % 4 == 0 ? long : i % 2 == 0 ? short : inner
            let pt = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

struct Star: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [sun.opacity(0.55), sun.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.42))
                .frame(width: size * 0.84, height: size * 0.84)
            Sparkle().fill(sun).frame(width: size, height: size)
            Circle().fill(sun).frame(width: size * 0.2, height: size * 0.2)
            Circle().fill(Color(red: 1, green: 0.97, blue: 0.85)).frame(width: size * 0.12, height: size * 0.12)
        }
    }
}

struct Sky: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 7
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(1 << 53)
            }
            for _ in 0..<140 {
                let r = next() < 0.12 ? 3.2 + next() * 2.5 : 1.2 + next() * 1.6
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.35 + next() * 0.55)))
            }
        }
        .background(.black)
    }
}

let gold = LinearGradient(colors: [sun, Color(red: 0.72, green: 0.5, blue: 0.05)], startPoint: .top, endPoint: .bottom)

// 3d chip seen from above at an angle, nova's star rising out of its core
struct IsoChip: View {

    var body: some View {
        Canvas { ctx, size in
            let cx = 512.0, cy = 590.0, a = 190.0, h = 60.0
            func iso(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
                CGPoint(x: cx + (x - y) * 0.866, y: cy + (x + y) * 0.5 - z)
            }
            func poly(_ pts: [CGPoint]) -> Path {
                var p = Path()
                p.move(to: pts[0])
                pts.dropFirst().forEach { p.addLine(to: $0) }
                p.closeSubpath()
                return p
            }
            func pin(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ z: Double) -> Path {
                poly([iso(x0, y0, z), iso(x1, y0, z), iso(x1, y1, z), iso(x0, y1, z)])
            }
            let goldShade = Gradient(colors: [Color(red: 1, green: 0.86, blue: 0.4), sun, Color(red: 0.6, green: 0.4, blue: 0.03)])
            let backPin = Color(red: 0.55, green: 0.38, blue: 0.04)

            // glow the chip floats over
            var glow = ctx
            glow.addFilter(.blur(radius: 70))
            glow.fill(Path(ellipseIn: CGRect(x: cx - 380, y: cy + 60, width: 760, height: 260)),
                      with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.13), .white.opacity(0)]),
                                            startPoint: CGPoint(x: cx - 380, y: 0), endPoint: CGPoint(x: cx + 380, y: 0)))

            // pins: back ones first, the body hides most of them
            let pinZ = h * 0.45, pinLen = 62.0, pinW = 26.0
            let spots: [Double] = [-140, -70, 0, 70, 140]
            for t in spots {
                ctx.fill(pin(t - pinW / 2, -a - pinLen, t + pinW / 2, -a, pinZ), with: .color(backPin))
                ctx.fill(pin(-a - pinLen, t - pinW / 2, -a, t + pinW / 2, pinZ), with: .color(backPin))
            }

            // body sides
            let top = [iso(-a, -a, h), iso(a, -a, h), iso(a, a, h), iso(-a, a, h)]
            let left = poly([iso(-a, a, h), iso(a, a, h), iso(a, a, 0), iso(-a, a, 0)])
            let right = poly([iso(a, a, h), iso(a, -a, h), iso(a, -a, 0), iso(a, a, 0)])
            ctx.fill(left, with: .linearGradient(Gradient(colors: [Color(white: 0.16), Color(white: 0.07)]), startPoint: iso(-a, a, h), endPoint: iso(a, a, 0)))
            ctx.fill(right, with: .linearGradient(Gradient(colors: [Color(white: 0.09), Color(white: 0.03)]), startPoint: iso(a, a, h), endPoint: iso(a, -a, 0)))

            var bevel = Path()
            bevel.move(to: iso(-a, a, h - 3)); bevel.addLine(to: iso(a, a, h - 3)); bevel.addLine(to: iso(a, -a, h - 3))
            ctx.stroke(bevel, with: .color(.white.opacity(0.12)), lineWidth: 2)

            // front pins catch the light
            for t in spots {
                let p1 = pin(t - pinW / 2, a, t + pinW / 2, a + pinLen, pinZ)
                ctx.fill(p1, with: .linearGradient(goldShade, startPoint: iso(t, a, pinZ), endPoint: iso(t, a + pinLen, pinZ)))
                let p2 = pin(a, t - pinW / 2, a + pinLen, t + pinW / 2, pinZ)
                ctx.fill(p2, with: .linearGradient(goldShade, startPoint: iso(a, t, pinZ), endPoint: iso(a + pinLen, t, pinZ)))
            }

            // polished top
            let face = poly(top)
            ctx.fill(face, with: .linearGradient(Gradient(colors: [Color(red: 0.13, green: 0.13, blue: 0.16), Color(red: 0.02, green: 0.02, blue: 0.03)]),
                                                 startPoint: top[0], endPoint: top[2]))
            var lit = ctx
            lit.clip(to: face)
            lit.fill(Path(ellipseIn: CGRect(x: cx - 260, y: cy - 150, width: 520, height: 300)),
                     with: .radialGradient(Gradient(colors: [sun.opacity(0.3), sun.opacity(0)]), center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: 210))
            // a soft reflection across the glass
            lit.fill(poly([iso(-a, -a, h), iso(a * 0.1, -a, h), iso(-a, a * 0.1, h)]), with: .linearGradient(Gradient(colors: [.white.opacity(0.11), .white.opacity(0)]), startPoint: iso(-a, -a, h), endPoint: iso(-a * 0.2, -a * 0.2, h)))

            // the die
            let d = a * 0.56
            let die = poly([iso(-d, -d, h), iso(d, -d, h), iso(d, d, h), iso(-d, d, h)])
            ctx.fill(die, with: .color(.black.opacity(0.35)))
            ctx.stroke(die, with: .color(sun.opacity(0.55)), lineWidth: 3)

            // rim light: bright where the light hits, fading round the chip
            var rim = Path()
            rim.move(to: top[3]); rim.addLine(to: top[0]); rim.addLine(to: top[1])
            ctx.stroke(rim, with: .linearGradient(Gradient(colors: [.white.opacity(0.15), .white.opacity(0.9), .white.opacity(0.15)]), startPoint: top[3], endPoint: top[1]), lineWidth: 3)
            var front = Path()
            front.move(to: top[3]); front.addLine(to: top[2]); front.addLine(to: top[1])
            ctx.stroke(front, with: .color(.white.opacity(0.35)), lineWidth: 2.5)
        }
    }
}

struct Flare: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [.clear, sun.opacity(0.7), Color(red: 1, green: 0.97, blue: 0.85), sun.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 900, height: 10)
                .blur(radius: 4)
            Capsule()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 520, height: 3)
        }
    }
}

struct Icon: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(white: 0.06), .black], center: .center, startRadius: 0, endRadius: 600)
            Sky().opacity(0.85).blendMode(.screen)
            IsoChip()
            Circle()
                .fill(RadialGradient(colors: [sun.opacity(0.45), sun.opacity(0.08), .clear], center: .center, startRadius: 0, endRadius: 280))
                .frame(width: 600, height: 600)
                .offset(y: -56)
                .blendMode(.screen)
            Star(size: 460).offset(y: -56)
            Flare().offset(y: -56).blendMode(.screen)
        }
        .frame(width: 1024, height: 1024)
        .clipped()
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    let image = renderer.nsImage!
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
