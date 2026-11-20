#if os(iOS)
import Foundation
import Vision
import CoreVideo
#if DEBUG && targetEnvironment(simulator)
import ImageIO

/// Only bundled illustrations can enter the Xcode rehearsal. The kiosk chooses a sample, never a verdict.
enum AttendanceDemoPortrait: String, Codable {
    case a, b

    func signature(forCapture: Bool) throws -> AttendanceFaceSignature {
        let name = rawValue + (forCapture ? "-capture" : "-reference")
        let side = AttendanceFaceSignature.side
        let unreadable = APIError.message("No se pudo leer el rostro de prueba incluido en JACNomina.")
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "attendance/samples"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == side, image.height == side else { throw unreadable }
        var pixels = [UInt8](repeating: 0, count: side * side)
        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw unreadable }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
        }
        guard let sample = AttendanceFaceSignature(alignedPixels: pixels.map { Float($0) }) else { throw unreadable }
        return sample
    }
}
#endif

/// A basic appearance comparison for the chosen employee, not a probability of identity.
struct AttendanceFaceSignature: Codable, Sendable {
    let texture: [Float]
    let tones: [Float]
    private var proportions: [Float]?
    static let side = 64
    // Uniform local binary patterns. Non-uniform patterns share the last bin.
    private static let patternBins: [Int] = {
        var bins = Array(repeating: 58, count: 256), next = 0
        for code in 0..<256 {
            let rotated = ((code << 1) | (code >> 7)) & 255
            if (code ^ rotated).nonzeroBitCount <= 2 { bins[code] = next; next += 1 }
        }
        return bins
    }()

    /// Samples only the inner facial oval. Eyes define scale, translation and in-plane rotation.
    static func capture(_ face: VNFaceObservation, in buffer: CVPixelBuffer) -> Self? {
        guard let marks = face.landmarks, let left = marks.leftEye, let right = marks.rightEye,
              left.pointCount > 0, right.pointCount > 0,
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let imageSize = CGSize(width: width, height: height)
        func eye(_ region: VNFaceLandmarkRegion2D) -> CGPoint {
            let points = region.pointsInImage(imageSize: imageSize)
            let x = points.reduce(0) { $0 + $1.x } / CGFloat(points.count)
            let y = points.reduce(0) { $0 + $1.y } / CGFloat(points.count)
            return CGPoint(x: x, y: CGFloat(height) - y)
        }
        let eyes = [eye(left), eye(right)].sorted { $0.x < $1.x }
        let dx = eyes[1].x - eyes[0].x, dy = eyes[1].y - eyes[0].y
        guard hypot(dx, dy) >= 32, abs(dy) < dx * 0.35 else { return nil }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        func luma(_ x: Int, _ y: Int) -> Double {
            let p = base + y * stride + x * 4
            return Double(29 * Int(p[0]) + 150 * Int(p[1]) + 77 * Int(p[2])) / 256
        }
        var pixels = [Float](repeating: 0, count: side * side)
        for y in 0..<side {
            for x in 0..<side {
                let u = CGFloat(x - 19) / 26, v = CGFloat(y - 23) / 26
                let sx = eyes[0].x + u * dx - v * dy, sy = eyes[0].y + u * dy + v * dx
                guard sx >= 0, sy >= 0, sx < CGFloat(width - 1), sy < CGFloat(height - 1) else { return nil }
                let ix = Int(sx), iy = Int(sy), fx = Double(sx) - Double(ix), fy = Double(sy) - Double(iy)
                let top = (1 - fx) * luma(ix, iy) + fx * luma(ix + 1, iy)
                let bottom = (1 - fx) * luma(ix, iy + 1) + fx * luma(ix + 1, iy + 1)
                pixels[y * side + x] = Float((1 - fy) * top + fy * bottom)
            }
        }
        guard var result = Self(alignedPixels: pixels), let nose = marks.nose, let mouth = marks.outerLips,
              let jaw = marks.faceContour else { return nil }
        let squareSpan = dx * dx + dy * dy
        func dimensions(_ region: VNFaceLandmarkRegion2D) -> (width: Float, depth: Float)? {
            guard region.pointCount >= 2 else { return nil }
            var minX = CGFloat.infinity, maxX = -CGFloat.infinity, sumY: CGFloat = 0
            for point in region.pointsInImage(imageSize: imageSize) {
                let x = point.x - eyes[0].x, y = CGFloat(height) - point.y - eyes[0].y
                let along = (x * dx + y * dy) / squareSpan
                minX = min(minX, along)
                maxX = max(maxX, along)
                sumY += (-x * dy + y * dx) / squareSpan
            }
            return (Float(maxX - minX), Float(sumY / CGFloat(region.pointCount)))
        }
        guard let n = dimensions(nose), let m = dimensions(mouth), let j = dimensions(jaw) else { return nil }
        result.proportions = [n.width, n.depth, m.width, m.depth, j.width]
        return result
    }

    init?(alignedPixels pixels: [Float]) {
        let size = Self.side
        guard pixels.count == size * size else { return nil }
        var bins = [Float](repeating: 0, count: 16 * 59)
        var sums = [Float](repeating: 0, count: 64), counts = sums
        let neighbors = [-size-1, -size, -size+1, 1, size+1, size, size-1, -1]
        for y in 2..<(size - 2) {
            for x in 2..<(size - 2) {
                let dx = Float(x - 32) / 25, dy = Float(y - 33) / 28
                guard dx * dx + dy * dy < 1 else { continue }
                let i = y * size + x, value = pixels[i]
                var pattern = 0
                for (bit, offset) in neighbors.enumerated() where pixels[i + offset] >= value {
                    pattern |= 1 << bit
                }
                bins[((y / 16) * 4 + x / 16) * 59 + Self.patternBins[pattern]] += 1
                let cell = (y / 8) * 8 + x / 8
                sums[cell] += value
                counts[cell] += 1
            }
        }
        // A normalized spatial tone pattern complements texture and discards overall brightness.
        var means = sums.indices.filter { counts[$0] >= 12 }.map { sums[$0] / counts[$0] }
        guard !means.isEmpty else { return nil }
        let average = means.reduce(0, +) / Float(means.count)
        means = means.map { $0 - average }
        let norm = sqrt(means.reduce(0) { $0 + $1 * $1 })
        guard average > 24, average < 236, norm / sqrt(Float(means.count)) >= 9 else { return nil }
        tones = means.map { $0 / norm }
        let area = counts.reduce(0, +)
        texture = bins.map { sqrt($0 / area) }
    }

    private func scores(_ other: Self) -> (tone: Float, texture: Float)? {
        guard texture.count == 16 * 59, other.texture.count == texture.count,
              !tones.isEmpty, other.tones.count == tones.count else { return nil }
        if let a = proportions, let b = other.proportions {
            guard a.count == 5, b.count == 5 else { return nil }
            let drift = zip(a, b).map { abs($0.0 - $0.1) }
            guard drift.allSatisfy({ $0 < 0.20 }), drift.reduce(0, +) < 0.48 else { return nil }
        } else if proportions != nil || other.proportions != nil { return nil }
        let tone = zip(tones, other.tones).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let overlap = zip(texture, other.texture).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        guard tone.isFinite, overlap.isFinite else { return nil }
        return (tone, overlap)
    }

    func resembles(_ other: Self) -> Bool {
        guard let score = scores(other) else { return false }
        return score.tone >= 0.88 && score.texture >= 0.84
    }

    /// For an open set, both the absolute similarity and separation from other references matter.
    func identified(in references: [String: Self]) -> String? {
        let ranked = references.compactMap { item -> (id: String, rank: Float, eligible: Bool)? in
            guard let score = scores(item.value) else { return nil }
            return (item.key, 0.65 * score.tone + 0.35 * score.texture,
                    score.tone >= 0.92 && score.texture >= 0.87)
        }.sorted { $0.rank > $1.rank }
        guard let best = ranked.first, best.eligible else { return nil }
        if ranked.count > 1, best.rank - ranked[1].rank < 0.045 { return nil }
        return best.id
    }
}
#endif
