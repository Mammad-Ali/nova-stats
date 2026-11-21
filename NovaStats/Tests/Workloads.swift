import Foundation
import Metal

// shared between the worker threads: a stop flag and how much work got done
final class WorkCounter {
    private let lock = NSLock()
    private var stoppedFlag = false
    private var units = 0.0
    private var errorCount = 0

    var stopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stoppedFlag
    }

    var errors: Int {
        lock.lock(); defer { lock.unlock() }
        return errorCount
    }

    func stop() {
        lock.lock(); stoppedFlag = true; lock.unlock()
    }

    func add(_ n: Double, errors: Int = 0) {
        lock.lock(); units += n; errorCount += errors; lock.unlock()
    }

    // what was done since the last call
    func take() -> Double {
        lock.lock(); defer { units = 0; lock.unlock() }
        return units
    }
}

private func now() -> Double { ProcessInfo.processInfo.systemUptime }

// MARK: cpu

enum CPUKernel: String, CaseIterable {
    case integer, float, sort
}

enum CPUWork {
    // whole-number hashing: the integer units
    @inline(never)
    static func integer(_ n: Int, seed: UInt64) -> UInt64 {
        var x = seed | 1
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for _ in 0..<n {
            x ^= x << 13
            x ^= x >> 7
            x ^= x << 17
            h = (h ^ x) &* 0x0000_0100_0000_01b3
            h = h &+ (h >> 29)
        }
        return h
    }

    // four independent chains of vector multiply-adds: the float units
    @inline(never)
    static func float(_ n: Int, seed: UInt64) -> UInt64 {
        let s = Float(seed & 7 + 1) * 0.1
        var a = SIMD4<Float>(1.0, 1.1, 1.2, 1.3) * s
        var b = SIMD4<Float>(0.9, 0.8, 0.7, 0.6) * s
        var c = SIMD4<Float>(0.5, 0.4, 0.3, 0.2) * s
        var d = SIMD4<Float>(0.1, 0.2, 0.3, 0.4) * s
        let m = SIMD4<Float>(0.9999, 1.0001, 0.9998, 1.0002)
        let k = SIMD4<Float>(repeating: 1e-4)
        for _ in 0..<n {
            a = a * m + k
            b = b * m + k
            c = c * m + k
            d = d * m + k
        }
        return UInt64((a + b + c + d).sum().bitPattern)
    }

    // fills an array with random numbers and sorts it: branches and cache
    @inline(never)
    static func sort(_ n: Int, seed: UInt64, buffer: inout [UInt32]) -> UInt64 {
        var x = seed | 1
        var sink: UInt64 = 0
        for _ in 0..<n {
            for i in buffer.indices {
                x ^= x << 13
                x ^= x >> 7
                x ^= x << 17
                buffer[i] = UInt32(truncatingIfNeeded: x)
            }
            buffer.sort()
            sink &+= UInt64(buffer[buffer.count / 2])
        }
        return sink &+ x
    }

    // how much work one call does: iterations, or arrays sorted
    static func chunk(_ kernel: CPUKernel) -> Int {
        kernel == .sort ? 32 : 1 << 20
    }

    // keeps `threads` threads busy until the counter stops
    static func start(threads: Int, kernel: CPUKernel = .float, counter: WorkCounter) {
        for i in 0..<threads {
            let thread = Thread {
                var sink = UInt64(i + 1)
                var buffer = [UInt32](repeating: 0, count: 1024)
                let n = chunk(kernel)
                while !counter.stopped {
                    switch kernel {
                    case .integer: sink = integer(n, seed: sink)
                    case .float: sink = float(n, seed: sink)
                    case .sort: sink = sort(n, seed: sink, buffer: &buffer)
                    }
                    counter.add(Double(n))
                }
                if sink == 42 { print("") } // keeps the compiler from dropping the work
            }
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    // work a second in each of `count` rounds, after a warm-up so the clocks are up
    static func rounds(threads: Int, kernel: CPUKernel, count: Int, seconds: Double) -> [Double] {
        let counter = WorkCounter()
        start(threads: threads, kernel: kernel, counter: counter)
        defer { counter.stop() }
        return timedRounds(counter, count: count, seconds: seconds)
    }
}

// reads a counter in `count` windows of `seconds`, after a one second warm-up
func timedRounds(_ counter: WorkCounter, count: Int, seconds: Double) -> [Double] {
    Thread.sleep(forTimeInterval: 1)
    _ = counter.take()
    var out: [Double] = []
    var begin = now()
    for _ in 0..<count {
        Thread.sleep(forTimeInterval: seconds)
        let done = counter.take()
        let end = now()
        out.append(done / (end - begin))
        begin = end
    }
    return out
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    let mid = sorted.count / 2
    return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}

// how far the rounds were apart, as a share of the median (±)
func spread(_ values: [Double]) -> Double {
    let mid = median(values)
    guard mid > 0, let low = values.min(), let high = values.max() else { return 0 }
    return (high - low) / 2 / mid
}

// MARK: gpu

final class GPUWork {
    static let threads = 1 << 20
    static let loops: UInt32 = 256
    // 8 float4 multiply-adds per loop, 8 flops each
    static let flopsPerDispatch = Double(threads) * Double(loops) * 8 * 8

    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let out: MTLBuffer

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: GPUWork.shader, options: nil),
              let function = library.makeFunction(name: "burn"),
              let pipeline = try? device.makeComputePipelineState(function: function),
              let out = device.makeBuffer(length: 1024 * 16, options: .storageModePrivate) else { return nil }
        self.queue = queue
        self.pipeline = pipeline
        self.out = out
    }

    // keeps the gpu busy until the counter stops, counting flops
    func start(counter: WorkCounter) {
        let thread = Thread { [self] in
            let inFlight = DispatchSemaphore(value: 3)
            while !counter.stopped {
                inFlight.wait()
                guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
                    inFlight.signal()
                    break
                }
                var loops = GPUWork.loops
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(out, offset: 0, index: 0)
                encoder.setBytes(&loops, length: 4, index: 1)
                encoder.dispatchThreads(MTLSize(width: GPUWork.threads, height: 1, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: min(256, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
                encoder.endEncoding()
                commands.addCompletedHandler { _ in
                    counter.add(GPUWork.flopsPerDispatch)
                    inFlight.signal()
                }
                commands.commit()
            }
            // let the last ones finish, then hand the slots back: a semaphore
            // freed below its starting count crashes
            for _ in 0..<3 { inFlight.wait() }
            for _ in 0..<3 { inFlight.signal() }
        }
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    // trillions of float operations a second, per round
    func rounds(count: Int, seconds: Double) -> [Double] {
        let counter = WorkCounter()
        start(counter: counter)
        defer { counter.stop() }
        return timedRounds(counter, count: count, seconds: seconds).map { $0 / 1e12 }
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void burn(device float4 *out [[buffer(0)]],
                     constant uint &loops [[buffer(1)]],
                     uint id [[thread_position_in_grid]]) {
        float4 a0 = float4(float(id) * 1e-6);
        float4 a1 = a0 + 0.1, a2 = a0 + 0.2, a3 = a0 + 0.3;
        float4 a4 = a0 + 0.4, a5 = a0 + 0.5, a6 = a0 + 0.6, a7 = a0 + 0.7;
        const float4 m = float4(0.9999);
        const float4 c = float4(0.0001);
        for (uint i = 0; i < loops; i++) {
            a0 = fma(a0, m, c); a1 = fma(a1, m, c); a2 = fma(a2, m, c); a3 = fma(a3, m, c);
            a4 = fma(a4, m, c); a5 = fma(a5, m, c); a6 = fma(a6, m, c); a7 = fma(a7, m, c);
        }
        out[id & 1023] = a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7;
    }
    """
}

// MARK: memory

enum MemoryWork {
    // copies a big buffer with every core: GB/s per round, counting the read and the write
    static func rounds(count: Int, seconds: Double) -> [Double] {
        let size = 512 << 20
        let src = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 64)
        let dst = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 64)
        defer {
            src.deallocate()
            dst.deallocate()
        }
        memset(src, 1, size)
        memset(dst, 0, size) // touch every page before timing
        let parts = ProcessInfo.processInfo.activeProcessorCount
        let part = size / parts
        func copy() {
            DispatchQueue.concurrentPerform(iterations: parts) { i in
                memcpy(dst + i * part, src + i * part, part)
            }
        }
        copy()
        var out: [Double] = []
        for _ in 0..<count {
            var bytes = 0.0
            let begin = now()
            repeat {
                copy()
                bytes += Double(part * parts) * 2
            } while now() - begin < seconds
            out.append(bytes / (now() - begin) / 1e9)
        }
        return out
    }

    // fills memory with patterns and checks every byte comes back the same
    static func stress(bytes total: Int, threads: Int, counter: WorkCounter) {
        let chunk = 64 << 20
        let chunks = max(total / chunk, threads)
        let per = max(chunks / threads, 1)
        for t in 0..<threads {
            let thread = Thread {
                let blocks = (0..<per).map { _ in UnsafeMutablePointer<UInt64>.allocate(capacity: chunk / 8) }
                defer { blocks.forEach { $0.deallocate() } }
                var pattern: UInt64 = 0xA5A5_5A5A_0F0F_F0F0 &+ UInt64(t)
                while !counter.stopped {
                    for block in blocks where !counter.stopped {
                        let words = chunk / 8
                        block.update(repeating: pattern, count: words)
                        var bad = 0
                        for i in 0..<words where block[i] != pattern { bad += 1 }
                        counter.add(Double(chunk) * 2, errors: bad)
                    }
                    pattern = ~pattern &+ 1
                }
            }
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }
}

// MARK: ssd

enum DiskWork {
    static let block = 8 << 20
    static var file: URL { FileManager.default.temporaryDirectory.appendingPathComponent("novastats-test.bin") }

    static var freeBytes: Int64 {
        let v = try? URL(fileURLWithPath: NSTemporaryDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // writes `size` bytes past the system cache, then reads them back: MB/s each way
    static func speed(size: Int = 4 << 30) -> (write: Double, read: [Double])? {
        guard freeBytes > Int64(size) * 3 else { return nil }
        defer { unlink(file.path) }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: block, alignment: 4096)
        defer { buffer.deallocate() }
        arc4random_buf(buffer, block)

        let out = open(file.path, O_CREAT | O_WRONLY | O_TRUNC, 0o600)
        guard out >= 0 else { return nil }
        _ = fcntl(out, F_NOCACHE, 1)
        var begin = now()
        var written = 0
        while written < size {
            let n = write(out, buffer, block)
            guard n > 0 else { close(out); return nil }
            written += n
        }
        _ = fcntl(out, F_FULLFSYNC)
        let writeSpeed = Double(written) / (now() - begin) / 1e6
        close(out)

        // read it back twice, past the cache both times
        var reads: [Double] = []
        for _ in 0..<2 {
            let input = open(file.path, O_RDONLY)
            guard input >= 0 else { return nil }
            _ = fcntl(input, F_NOCACHE, 1)
            begin = now()
            var readBytes = 0
            while true {
                let n = read(input, buffer, block)
                if n <= 0 { break }
                readBytes += n
            }
            reads.append(Double(readBytes) / (now() - begin) / 1e6)
            close(input)
        }
        return (writeSpeed, reads)
    }

    // the file is written once, then only read from: reads don't wear the ssd out
    static func stress(counter: WorkCounter, size: Int = 2 << 30) -> Bool {
        guard freeBytes > Int64(size) * 3 else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: block, alignment: 4096)
        arc4random_buf(buffer, block)
        let out = open(file.path, O_CREAT | O_WRONLY | O_TRUNC, 0o600)
        guard out >= 0 else { buffer.deallocate(); return false }
        _ = fcntl(out, F_NOCACHE, 1) // or the reads would come from memory, not the ssd
        var written = 0
        while written < size {
            let n = write(out, buffer, block)
            if n <= 0 { break }
            written += n
        }
        close(out)
        buffer.deallocate()

        let threads = 4
        let finished = DispatchGroup()
        for _ in 0..<threads {
            finished.enter()
            let thread = Thread {
                let input = open(file.path, O_RDONLY)
                let readBuffer = UnsafeMutableRawPointer.allocate(byteCount: block, alignment: 4096)
                defer {
                    readBuffer.deallocate()
                    if input >= 0 { close(input) }
                    finished.leave()
                }
                guard input >= 0 else { return }
                _ = fcntl(input, F_NOCACHE, 1)
                let blocks = written / block
                while !counter.stopped {
                    let offset = off_t(Int.random(in: 0..<blocks) * block)
                    let n = pread(input, readBuffer, block, offset)
                    if n > 0 { counter.add(Double(n)) }
                }
            }
            thread.qualityOfService = .userInitiated
            thread.start()
        }
        // tidy up once every reader is done
        finished.notify(queue: .global()) { unlink(file.path) }
        return true
    }
}
