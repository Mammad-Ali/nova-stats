import SwiftUI
import MetalKit

// port of Nova's 3D sky: stars fly toward you, faster with the cpu load,
// the camera leans to the mouse, and a swarm of particles orbits the middle
final class Sky {
    struct Star {
        var x, y, z: Double
        let size, twinkle, phase: Double
    }

    struct Orbiter {
        var pos: CGPoint
        var vel: CGVector
        let mass: Double
    }

    private let gm = 26000.0
    private let softening = 40.0
    private let cursorPush = 42000.0
    private let cursorRadius = 130.0

    var stars: [Star] = []
    var orbiters: [Orbiter] = []
    var level = 0.0
    var cursor: CGPoint?
    var time = 0.0
    var flight = 0.06
    var look = CGPoint.zero

    private var size = CGSize.zero
    private var lastDate: Date?

    init() {
        for _ in 0..<420 {
            stars.append(newStar(z: 0.04 + .random(in: 0...0.96)))
        }
    }

    private func newStar(z: Double) -> Star {
        let big = Double.random(in: 0..<1) < 0.1
        return Star(x: .random(in: -1.6...1.6),
                    y: .random(in: -1.1...1.1),
                    z: z,
                    size: big ? 1.6 + .random(in: 0...1.2) : 0.6 + .random(in: 0...0.8),
                    twinkle: 0.4 + .random(in: 0...2),
                    phase: .random(in: 0...(2 * .pi)))
    }

    func center(_ size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.42)
    }

    func step(to date: Date, size: CGSize) {
        let dt = lastDate.map { min(max(date.timeIntervalSince($0), 0), 0.05) } ?? 0.016
        lastDate = date
        if orbiters.isEmpty && size.width > 0 { seed(size) }
        self.size = size
        time += dt

        flight = 0.06 + 0.42 * level
        for i in stars.indices {
            stars[i].z -= flight * dt
            if stars[i].z <= 0.035 { stars[i] = newStar(z: 1 + .random(in: 0...0.04)) }
        }

        let target = cursor.map {
            CGPoint(x: $0.x / max(size.width, 1) * 2 - 1, y: $0.y / max(size.height, 1) * 2 - 1)
        } ?? .zero
        let k = 1 - exp(-dt * 2.2)
        look.x += (target.x - look.x) * k
        look.y += (target.y - look.y) * k

        let c = center(size)
        let maxR = max(size.width, size.height) * 0.62
        for i in orbiters.indices {
            var o = orbiters[i]
            let dx = c.x - o.pos.x, dy = c.y - o.pos.y
            let r2 = dx * dx + dy * dy + softening * softening
            let inv = 1 / sqrt(r2)
            var ax = dx * inv * gm / r2
            var ay = dy * inv * gm / r2

            if let cursor {
                let ox = o.pos.x - cursor.x, oy = o.pos.y - cursor.y
                let d = sqrt(ox * ox + oy * oy)
                if d < cursorRadius && d > 0.001 {
                    let push = cursorPush / (d * d + 400)
                    ax += ox / d * push
                    ay += oy / d * push
                }
            }

            o.vel.dx += ax * dt
            o.vel.dy += ay * dt
            o.pos.x += o.vel.dx * dt
            o.pos.y += o.vel.dy * dt

            // pull escapees back so the swarm doesn't empty out
            let ex = o.pos.x - c.x, ey = o.pos.y - c.y
            let dist = sqrt(ex * ex + ey * ey)
            if dist > maxR {
                o.vel.dx = o.vel.dx * 0.9 - ex / dist * 40
                o.vel.dy = o.vel.dy * 0.9 - ey / dist * 40
            }
            orbiters[i] = o
        }
    }

    private func seed(_ size: CGSize) {
        let c = center(size)
        let short = min(size.width, size.height)
        let minR = short * 0.16, maxR = short * 0.52
        for _ in 0..<80 {
            let angle = Double.random(in: 0...(2 * .pi))
            let radius = Double.random(in: minR...maxR)
            let v = sqrt(gm / radius) * .random(in: 0.88...1.12)
            let dir: Double = Bool.random() ? 1 : -1
            orbiters.append(Orbiter(
                pos: CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius),
                vel: CGVector(dx: -sin(angle) * v * dir, dy: cos(angle) * v * dir),
                mass: .random(in: 0.6...1.4)))
        }
    }
}

struct Starfield: NSViewRepresentable {
    let sky: Sky
    var level: Double

    func makeCoordinator() -> StarRenderer { StarRenderer(sky: sky) }

    func makeNSView(context: Context) -> MTKView {
        let view = PassThroughMTKView(frame: .zero, device: context.coordinator.device)
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.target = level
    }
}

final class PassThroughMTKView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { true }
}

// draws the sky on the gpu so swiftui doesn't have to redo the layout every frame
final class StarRenderer: NSObject, MTKViewDelegate {
    struct Dot {
        var a: SIMD2<Float>
        var b: SIMD2<Float>
        var radius: Float
        var alpha: Float
    }

    let sky: Sky
    let device = MTLCreateSystemDefaultDevice()!
    var target = 0.0

    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var buffers: [MTLBuffer] = []
    private var frame = 0
    private let inFlight = DispatchSemaphore(value: 3)
    private var dots: [Dot] = []
    private weak var view: MTKView?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var locked = false

    init(sky: Sky) {
        self.sky = sky
        super.init()
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }

    func attach(_ view: MTKView) {
        self.view = view
        view.delegate = self
        queue = device.makeCommandQueue()

        let library = try? device.makeLibrary(source: starShader, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library?.makeFunction(name: "star_vertex")
        desc.fragmentFunction = library?.makeFunction(name: "star_fragment")
        let color = desc.colorAttachments[0]!
        color.pixelFormat = view.colorPixelFormat
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try? device.makeRenderPipelineState(descriptor: desc)

        let size = MemoryLayout<Dot>.stride * (sky.stars.count + 100)
        buffers = (0..<3).compactMap { _ in device.makeBuffer(length: size, options: .storageModeShared) }

        // stop drawing while nobody can see it: window covered or minimized,
        // screen locked, display asleep
        watch(NotificationCenter.default, NSWindow.didChangeOcclusionStateNotification) { _ in }
        watch(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        watch(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification) { $0.locked = true }
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification) { $0.locked = false }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        locked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        updatePause()
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name, _ change: @escaping (StarRenderer) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            change(self)
            self.updatePause()
        }
        observers.append((center, token))
    }

    private func updatePause() {
        guard let view else { return }
        let visible = view.window.map { $0.occlusionState.contains(.visible) } ?? true
        view.isPaused = locked || !visible
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let size = view.bounds.size
        guard size.width > 0, let pipeline, let queue, !buffers.isEmpty else { return }

        sky.level += (target - sky.level) * 0.05
        sky.step(to: Date(), size: size)
        let scale = Float(view.drawableSize.width / size.width)
        fill(size, scale)

        // drop the frame rather than block the main thread waiting for the gpu
        guard inFlight.wait(timeout: .now()) == .success else { return }
        let buffer = buffers[frame % buffers.count]
        frame += 1
        let count = min(dots.count, buffer.length / MemoryLayout<Dot>.stride)
        dots.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: count * MemoryLayout<Dot>.stride) }

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        var viewport = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        if count > 0 {
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        commands.commit()
    }

    private func fill(_ size: CGSize, _ scale: Float) {
        dots.removeAll(keepingCapacity: true)
        let c = sky.center(size)
        let focal = min(size.width, size.height) * 0.55
        let cam = CGPoint(x: sky.look.x * 0.22, y: sky.look.y * 0.14)
        let trail = sky.flight * 0.05

        func project(_ x: Double, _ y: Double, _ z: Double) -> SIMD2<Float> {
            SIMD2(Float(c.x + (x - cam.x) / z * focal) * scale, Float(c.y + (y - cam.y) / z * focal) * scale)
        }

        let w = Float(size.width) * scale, h = Float(size.height) * scale, edge = 40 * scale
        for s in sky.stars {
            let head = project(s.x, s.y, s.z)
            guard head.x > -edge, head.x < w + edge, head.y > -edge, head.y < h + edge else { continue }
            let near = 1 - s.z
            let tw = 0.7 + 0.3 * sin(sky.time * s.twinkle + s.phase)
            let appear = min(max((1 - s.z) / 0.3, 0), 1) // born far and faint, nothing pops in
            let alpha = Float(min(max((0.18 + 0.82 * near) * tw * appear, 0), 1))
            let radius = Float(min(max(s.size * 0.16 / s.z, 0.35), 3.4)) * scale

            let tail = project(s.x, s.y, s.z + trail)
            let d = head - tail
            if (d.x * d.x + d.y * d.y) / (scale * scale) > 2.5 {
                dots.append(Dot(a: tail, b: head, radius: radius * 0.6, alpha: alpha))
            } else {
                dots.append(Dot(a: head, b: head, radius: radius, alpha: alpha))
            }
        }

        for o in sky.orbiters {
            let p = SIMD2(Float(o.pos.x) * scale, Float(o.pos.y) * scale)
            let alpha = Float(min((0.35 + 0.35 * sky.level) * o.mass, 0.95))
            dots.append(Dot(a: p, b: p, radius: Float(1.1 + 1.5 * o.mass) * scale, alpha: alpha))
        }
    }
}

// compiled at launch, so the project builds without the metal toolchain
private let starShader = """
#include <metal_stdlib>
using namespace metal;

// one star: a round-capped segment from a (tail) to b (head), in pixels
struct Dot {
    float2 a;
    float2 b;
    float radius;
    float alpha;
};

struct Out {
    float4 position [[position]];
    float2 p;
    float2 a;
    float2 b;
    float radius;
    float alpha;
};

vertex Out star_vertex(uint vid [[vertex_id]],
                       uint iid [[instance_id]],
                       const device Dot *dots [[buffer(0)]],
                       constant float2 &viewport [[buffer(1)]]) {
    Dot d = dots[iid];
    float2 dir = d.b - d.a;
    float len = length(dir);
    float2 u = len > 0.001 ? dir / len : float2(1, 0);
    float2 n = float2(-u.y, u.x);
    float pad = d.radius + 1.0;
    float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
    float2 p = (d.a + d.b) * 0.5 + u * corner.x * (len * 0.5 + pad) + n * corner.y * pad;

    Out o;
    o.position = float4(p.x / viewport.x * 2 - 1, 1 - p.y / viewport.y * 2, 0, 1);
    o.p = p;
    o.a = d.a;
    o.b = d.b;
    o.radius = d.radius;
    o.alpha = d.alpha;
    return o;
}

fragment float4 star_fragment(Out in [[stage_in]]) {
    float2 pa = in.p - in.a;
    float2 ba = in.b - in.a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    float dist = length(pa - ba * h);
    float a = in.alpha * clamp(in.radius + 0.5 - dist, 0.0, 1.0);
    return float4(a, a, a, a);
}
"""
