import Accelerate
import CoreMedia
import Foundation
import VideoToolbox

private func now() -> Double { ProcessInfo.processInfo.systemUptime }

// single-precision matrix multiply through Accelerate, which runs it on the
// chip's matrix units: the kind of math AI and photo apps lean on
enum MatrixWork {
    static let n = 2048

    // trillions of float operations a second, per round
    static func rounds(count: Int, seconds: Double) -> [Double] {
        let size = n * n
        var a = [Float](repeating: 0, count: size)
        var b = [Float](repeating: 0, count: size)
        var c = [Float](repeating: 0, count: size)
        for i in 0..<size {
            a[i] = Float(i % 97) * 0.01
            b[i] = Float(i % 89) * 0.01
        }
        let dim = Int32(n)
        func multiply() {
            cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, dim, dim, dim, 1, a, dim, b, dim, 0, &c, dim)
        }
        let warm = now()
        while now() - warm < 1 { multiply() }

        let flops = 2 * Double(n) * Double(n) * Double(n)
        var out: [Double] = []
        for _ in 0..<count {
            var calls = 0
            let begin = now()
            repeat {
                multiply()
                calls += 1
            } while now() - begin < seconds
            out.append(Double(calls) * flops / (now() - begin) / 1e12)
        }
        withExtendedLifetime(c) {}
        return out
    }
}

// 4k hevc through the hardware video encoder, as fast as it goes
enum VideoWork {
    static let width = 3840
    static let height = 2160

    // frames a second, per round
    static func rounds(count: Int, seconds: Double) -> [Double] {
        var made: VTCompressionSession?
        let spec = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true] as CFDictionary
        VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
                                   codecType: kCMVideoCodecType_HEVC, encoderSpecification: spec,
                                   imageBufferAttributes: nil, compressedDataAllocator: nil,
                                   outputCallback: nil, refcon: nil, compressionSessionOut: &made)
        guard let session = made else { return [] }
        defer { VTCompressionSessionInvalidate(session) }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        VTCompressionSessionPrepareToEncodeFrames(session)

        // a few frames of noise, so every frame is new work for the encoder
        let frames = (0..<6).compactMap { _ in noiseFrame() }
        guard !frames.isEmpty else { return [] }

        let counter = WorkCounter()
        let slots = 6
        let inFlight = DispatchSemaphore(value: slots)
        var number: Int64 = 0
        func encodeUntil(_ end: Double) {
            while now() < end {
                inFlight.wait()
                let frame = frames[Int(number) % frames.count]
                let time = CMTime(value: number, timescale: 60)
                number += 1
                let status = VTCompressionSessionEncodeFrame(session, imageBuffer: frame, presentationTimeStamp: time,
                                                             duration: CMTime(value: 1, timescale: 60),
                                                             frameProperties: nil, infoFlagsOut: nil) { _, _, _ in
                    counter.add(1)
                    inFlight.signal()
                }
                if status != noErr { inFlight.signal() }
            }
        }

        encodeUntil(now() + 1) // warm up
        _ = counter.take()
        var out: [Double] = []
        var begin = now()
        for _ in 0..<count {
            encodeUntil(begin + seconds)
            let done = counter.take()
            let end = now()
            out.append(done / (end - begin))
            begin = end
        }
        // wait for every frame, so the semaphore is back to where it started
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        return out
    }

    private static func noiseFrame() -> CVPixelBuffer? {
        var made: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                            attributes, &made)
        guard let buffer = made else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        for plane in 0..<CVPixelBufferGetPlaneCount(buffer) {
            if let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) {
                arc4random_buf(base, CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) * CVPixelBufferGetHeightOfPlane(buffer, plane))
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}
