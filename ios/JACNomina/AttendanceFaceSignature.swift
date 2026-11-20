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

/// The weakest usable similarity is 0.10 on this comparison scale. It is not a probability.
enum AttendanceFaceMatch: Equatable, Sendable {
    case automatic(String)
    case suggested(String)
    case needsCode([String])
    case unknown

    var automaticID: String? {
        if case let .automatic(id) = self { return id }
        return nil
    }

    func includes(_ id: String) -> Bool {
        switch self {
        case let .automatic(match), let .suggested(match): return id == match
        case let .needsCode(matches): return matches.contains(id)
        case .unknown: return false
        }
    }

    static func choose(_ similarities: [String: Float]) -> Self {
        let ranked = similarities.filter { $0.value.isFinite }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard let first = ranked.first, first.value >= 0.10 else { return .unknown }
        let contenders = ranked.prefix { $0.value >= 0.10 && first.value - $0.value <= 0.025 }
        if contenders.count > 1 { return .needsCode(contenders.map(\.key)) }
        let runnerUp = ranked.dropFirst().first
        // Even the minimum evidence can identify an employee when it separates them from the roster.
        // With a single enrollment a weak similarity has no runner-up for comparison.
        if first.value >= 0.86 || runnerUp.map({ first.value - $0.value >= 0.05 }) == true {
            return .automatic(first.key)
        }
        return .suggested(first.key)
    }
}

struct AttendanceFaceSignature: Codable, Sendable {
    let texture: [Float]
    let tones: [Float]
    private var proportions: [Float]?
    static let side = 64

    private static func insideFace(x: Int, y: Int) -> Bool {
        let dx = Float(x - 32) / 25, dy = Float(y - 33) / 28
        return dx * dx + dy * dy < 1
    }

    private static let facePixels = (0..<(side * side)).filter { insideFace(x: $0 % side, y: $0 / side) }
    // Mean pixel coordinates of the very same cells kept in existing enrolled tone vectors.
    // Removing both axes discounts a change of lighting from either side of the kiosk.
    private static let lightingAxes: (x: [Float], y: [Float]) = {
        var x = [Float](repeating: 0, count: 64), y = x, counts = x
        for pixel in facePixels {
            let col = pixel % side, row = pixel / side, cell = (row / 8) * 8 + col / 8
            x[cell] += Float(col)
            y[cell] += Float(row)
            counts[cell] += 1
        }
        let indices = counts.indices.filter { counts[$0] >= 12 }
        func centered(_ sums: [Float]) -> [Float] {
            let means = indices.map { sums[$0] / counts[$0] }
            let mean = means.reduce(0, +) / Float(means.count)
            return means.map { $0 - mean }
        }
        let horizontal = unit(centered(x)), vertical = centered(y)
        let cross = dot(horizontal, vertical)
        return (horizontal, unit(zip(vertical, horizontal).map { $0 - cross * $1 }))
    }()

    private static func dot(_ lhs: [Float], _ rhs: [Float]) -> Float {
        zip(lhs, rhs).reduce(Float.zero) { $0 + $1.0 * $1.1 }
    }

    private static func unit(_ vector: [Float]) -> [Float] {
        let norm = sqrt(dot(vector, vector))
        return norm.isFinite && norm > 0.0001 ? vector.map { $0 / norm } : []
    }

    private var correctedTones: [Float]? {
        let axes = Self.lightingAxes
        guard tones.count == axes.x.count else { return nil }
        let x = Self.dot(tones, axes.x), y = Self.dot(tones, axes.y)
        let residual = tones.indices.map { tones[$0] - x * axes.x[$0] - y * axes.y[$0] }
        let result = Self.unit(residual)
        return result.isEmpty ? nil : result
    }
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
        guard hypot(dx, dy) >= 24, abs(dy) < dx * 0.6, width > 1, height > 1 else { return nil }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        func luma(_ x: Int, _ y: Int) -> Double {
            let p = base + y * stride + x * 4
            return Double(29 * Int(p[0]) + 150 * Int(p[1]) + 77 * Int(p[2])) / 256
        }
        var pixels = [Float](repeating: 0, count: side * side)
        var clipped = 0
        for y in 0..<side {
            for x in 0..<side {
                let u = CGFloat(x - 19) / 26, v = CGFloat(y - 23) / 26
                let rawX = eyes[0].x + u * dx - v * dy, rawY = eyes[0].y + u * dy + v * dx
                let sx = min(max(0, rawX), CGFloat(width - 1)), sy = min(max(0, rawY), CGFloat(height - 1))
                if (sx != rawX || sy != rawY) && Self.insideFace(x: x, y: y) { clipped += 1 }
                let ix = min(Int(sx), width - 2), iy = min(Int(sy), height - 2)
                let fx = Double(sx) - Double(ix), fy = Double(sy) - Double(iy)
                let top = (1 - fx) * luma(ix, iy) + fx * luma(ix + 1, iy)
                let bottom = (1 - fx) * luma(ix, iy + 1) + fx * luma(ix + 1, iy + 1)
                pixels[y * side + x] = Float((1 - fy) * top + fy * bottom)
            }
        }
        guard clipped <= facePixels.count / 10, var result = Self(alignedPixels: pixels) else { return nil }
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
        if let nose = marks.nose, let mouth = marks.outerLips, let jaw = marks.faceContour,
           let n = dimensions(nose), let m = dimensions(mouth), let j = dimensions(jaw) {
            result.proportions = [n.width, n.depth, m.width, m.depth, j.width]
        }
        return result
    }

    init?(alignedPixels pixels: [Float]) {
        let size = Self.side
        guard pixels.count == size * size else { return nil }
        var bins = [Float](repeating: 0, count: 16 * 59)
        var sums = [Float](repeating: 0, count: 64), counts = sums
        let neighbors = [-size-1, -size, -size+1, 1, size+1, size, size-1, -1]
        for i in Self.facePixels {
            let x = i % size, y = i / size, value = pixels[i]
            var pattern = 0
            for (bit, offset) in neighbors.enumerated() where pixels[i + offset] >= value {
                pattern |= 1 << bit
            }
            bins[((y / 16) * 4 + x / 16) * 59 + Self.patternBins[pattern]] += 1
            let cell = (y / 8) * 8 + x / 8
            sums[cell] += value
            counts[cell] += 1
        }
        // A normalized spatial tone pattern complements texture and discards overall brightness.
        var means = sums.indices.filter { counts[$0] >= 12 }.map { sums[$0] / counts[$0] }
        guard !means.isEmpty else { return nil }
        let average = means.reduce(0, +) / Float(means.count)
        means = means.map { $0 - average }
        let norm = sqrt(means.reduce(0) { $0 + $1 * $1 })
        guard average > 12, average < 246, norm / sqrt(Float(means.count)) >= 4 else { return nil }
        tones = means.map { $0 / norm }
        let area = counts.reduce(0, +)
        texture = bins.map { sqrt($0 / area) }
    }

    private init(texture: [Float], tones: [Float], proportions: [Float]?) {
        self.texture = texture
        self.tones = tones
        self.proportions = proportions
    }

    static func mean(of samples: [Self]) -> Self? {
        guard let first = samples.first, samples.allSatisfy({
            $0.texture.count == 16 * 59 && $0.tones.count == Self.lightingAxes.x.count
        }) else { return nil }
        func normalizedSum(_ values: [[Float]]) -> [Float] {
            var sum = Array(repeating: Float.zero, count: values[0].count)
            for vector in values {
                for i in sum.indices { sum[i] += vector[i] }
            }
            return Self.unit(sum)
        }
        let shapes = samples.compactMap(\.proportions).filter { $0.count == 5 }
        let shape = shapes.first?.indices.map { index in
            shapes.reduce(Float.zero) { $0 + $1[index] } / Float(shapes.count)
        }
        let tones = normalizedSum(samples.map(\.tones))
        guard tones.count == first.tones.count else { return nil }
        return Self(texture: normalizedSum(samples.map(\.texture)), tones: tones, proportions: shape)
    }

    /// Duplicate enrollment uses the original, stricter comparison.
    func resembles(_ other: Self) -> Bool {
        guard texture.count == 16 * 59, other.texture.count == texture.count,
              tones.count == Self.lightingAxes.x.count, other.tones.count == tones.count else { return false }
        if let a = proportions, let b = other.proportions {
            guard a.count == 5, b.count == 5 else { return false }
            let drift = zip(a, b).map { abs($0.0 - $0.1) }
            guard drift.allSatisfy({ $0 < 0.20 }), drift.reduce(0, +) < 0.48 else { return false }
        }
        return Self.dot(tones, other.tones) >= 0.88 && Self.dot(texture, other.texture) >= 0.84
    }

    private func similarity(to other: Self, corrected: [Float]) -> Float? {
        guard texture.count == 16 * 59, other.texture.count == texture.count,
              let reference = other.correctedTones else { return nil }
        var score = 0.8 * Self.dot(corrected, reference) + 0.2 * Self.dot(texture, other.texture)
        if let a = proportions, let b = other.proportions, a.count == 5, b.count == 5 {
            let drift = zip(a, b).reduce(Float.zero) { $0 + min(0.35, abs($1.0 - $1.1)) }
            score -= 0.10 * drift
        }
        return score.isFinite ? score : nil
    }

    func continuesReading(_ other: Self) -> Bool {
        guard let corrected = correctedTones, let score = similarity(to: other, corrected: corrected) else { return false }
        return score >= 0.85
    }

    func match(in references: [String: Self]) -> AttendanceFaceMatch {
        guard let corrected = correctedTones else { return .unknown }
        return .choose(references.compactMapValues { similarity(to: $0, corrected: corrected) })
    }
}
#endif
