import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import Vision

/// Structured fields supplied with one private boarding attachment. Optional
/// fields distinguish absent data from an explicitly unassigned seat ("").
struct BoardingMessageDetails: Codable, Hashable, Sendable {
    var seat: String? = nil
    var departureTime: String? = nil
    var boardingTime: String? = nil
    var airline: String? = nil

    var validated: BoardingMessageDetails {
        let normalizedSeat: String? = seat.flatMap { value in
            if value.isEmpty { return "" }
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard value.range(of: "^[0-9]{1,3}[A-Z]?$", options: .regularExpression) != nil,
                  value.range(of: "^0+[A-Z]?$", options: .regularExpression) == nil else { return nil }
            return value.replacingOccurrences(of: "^0+(?=[0-9])", with: "", options: .regularExpression)
        }
        let normalizedAirline: String? = airline.flatMap { value in
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 80,
                  !value.unicodeScalars.contains(where: { $0.value < 32 || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) }) else { return nil }
            return value
        }
        return BoardingMessageDetails(seat: normalizedSeat,
                                      departureTime: departureTime.flatMap(BoardingWalletDetailsExtractor.normalizedTime),
                                      boardingTime: boardingTime.flatMap(BoardingWalletDetailsExtractor.normalizedTime),
                                      airline: normalizedAirline)
    }
    var hasCardFields: Bool { seat != nil || departureTime != nil || boardingTime != nil || airline != nil }
    var completesCard: Bool { seat != nil && departureTime != nil }
    func applying(to original: BoardingCardDetails = BoardingCardDetails()) -> BoardingCardDetails {
        let value = validated
        return BoardingCardDetails(seat: value.seat ?? original.seat,
                                   departureTime: value.departureTime ?? original.departureTime,
                                   explicitBoardingTime: value.boardingTime ?? original.explicitBoardingTime,
                                   airline: value.airline ?? original.airline)
    }
    func applying(to original: BoardingWalletDetails) -> BoardingWalletDetails {
        let value = validated
        var result = original
        if let seat = value.seat { result.seat = seat }
        if let departure = value.departureTime { result.departureTime = departure }
        if let boarding = value.boardingTime { result.boardingTime = boarding }
        return result
    }
}

/// Slack's explicit room time takes priority. Without that field, preserve
/// JAC's one-hour civil reminder; the PDF's boarding time remains unchanged.
struct BoardingCardDetails: Equatable, Sendable {
    var seat: String = ""
    var departureTime: String = ""
    var explicitBoardingTime: String? = nil
    var airline: String = ""
    private var departureMinutes: Int? {
        guard let normalized = BoardingWalletDetailsExtractor.normalizedTime(departureTime) else { return nil }
        let parts = normalized.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }
    var boardingTime: String {
        if let explicitBoardingTime, let time = BoardingWalletDetailsExtractor.normalizedTime(explicitBoardingTime) { return time }
        guard let departureMinutes else { return "" }
        let minutes = (departureMinutes + 1440 - 60) % 1440
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
    var boardingPreviousDay: Bool {
        guard let departureMinutes else { return false }
        if explicitBoardingTime != nil, let time = BoardingWalletDetailsExtractor.normalizedTime(boardingTime) {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && parts[0] * 60 + parts[1] > departureMinutes
        }
        return departureMinutes < 60
    }
}

enum BoardingCardDetailsExtractor {
    static func extract(_ data: Data, mime: String) throws -> BoardingCardDetails {
        try BoardingWalletDetailsExtractor.cardDetails(data: data, mime: mime)
    }
}

struct BoardingWalletDetails: Codable, Equatable, Sendable {
    var passenger: String = ""
    var origin: String = ""
    var destination: String = ""
    var departureTime: String = ""
    var boardingTime: String = ""
    var seat: String = ""
}

struct BoardingWalletLeg: Identifiable, Equatable, Sendable {
    let index: Int
    var details: BoardingWalletDetails
    var id: Int { index }
    var label: String {
        guard !details.origin.isEmpty || !details.destination.isEmpty else { return "Tramo \(index + 1)" }
        return "Tramo \(index + 1): \(details.origin) → \(details.destination)"
    }
}

/// Suggestions for the user's review. Neither BCBP nor OCR changes the original
/// barcode. Times are civil strings read from explicit document labels, never
/// inferred from an itinerary, device timezone, arrival time, or airline code.
enum BoardingWalletDetailsExtractor {
    private static let maximumBytes = 10 * 1024 * 1024
    private static let maximumText = 12_000
    private enum Field: String, CaseIterable, Hashable {
        case passenger, origin, destination, departureTime, boardingTime, seat, stop
    }
    private static let labelPatterns: [(Field, String)] = [
        (.stop, "BOARDING\\s+(?:PASS|CARD)|(?:PASE|TARJETA)\\s+DE\\s+EMBARQUE|PUERTA\\s+DE\\s+SALIDA|DEPARTURE\\s+GATE"),
        (.departureTime, "HORA\\s+(?:DEL\\s+VUELO|DE\\s+SALIDA)|FLIGHT\\s+TIME|DEPARTURE(?:\\s+TIME)?|SALIDA"),
        (.boardingTime, "HORA\\s+EN\\s+SALA|HORA\\s+DE\\s+EMBARQUE|BOARDING(?:\\s+TIME)?|EMBARQUE|PRESENTARSE(?:\\s+EN\\s+SALA)?"),
        (.passenger, "NOMBRE\\s+DEL\\s+PASAJERO|PASSENGER\\s+NAME|PASAJERO(?:\\(A\\))?|PASSENGER|NOMBRE|NAME"),
        (.origin, "ORIGEN|FROM"), (.destination, "DESTINO|TO"), (.seat, "ASIENTO|SEAT|SILLA"),
        (.stop, "HORA\\s+DE\\s+LLEGADA|ARRIVAL(?:\\s+TIME)?|LLEGADA|PUERTA|GATE|SALA|VUELO|FLIGHT|FECHA|DATE|GRUPO|GROUP")
    ]

    static func legs(barcode: BoardingWalletBarcode) -> [BoardingWalletLeg] {
        let bytes = Array(barcode.message.utf8)
        guard bytes.count >= 60, bytes[0] == 77, (49...52).contains(bytes[1]) else { return [] }
        let count = Int(bytes[1] - 48)
        func part(_ start: Int, _ length: Int) -> String? {
            guard start >= 0, start + length <= bytes.count else { return nil }
            return String(bytes: bytes[start..<(start + length)], encoding: .ascii)
        }
        guard let rawName = part(2, 20), matches(rawName, "^[A-Z ./'-]{1,20}$"), rawName.filter({ $0 == "/" }).count <= 1,
              let indicator = part(22, 1), indicator == "E" || indicator == " " else { return [] }
        let pieces = rawName.split(separator: "/", omittingEmptySubsequences: false).map { clean(String($0)) }
        let passenger = pieces.count == 2 ? clean(pieces[1] + " " + pieces[0]) : clean(rawName)
        var result: [BoardingWalletLeg] = [], offset = 23
        for index in 0..<count {
            guard let from = part(offset + 7, 3), let to = part(offset + 10, 3),
                  matches(from, "^[A-Z]{3}$"), matches(to, "^[A-Z]{3}$"), from != to,
                  let carrier = part(offset + 13, 3), matches(carrier, "^[A-Z0-9]{2}[A-Z0-9 ]$"),
                  let flight = part(offset + 16, 5), matches(flight, "^[ A-Z0-9]{5}$"), flight.contains(where: { $0.isNumber }),
                  let day = part(offset + 21, 3), matches(day, "^[0-9]{3}$"), let ordinal = Int(day), (1...366).contains(ordinal),
                  let rawSeat = part(offset + 25, 4), let size = part(offset + 35, 2), matches(size, "^[0-9A-Fa-f]{2}$"),
                  let variable = Int(size, radix: 16), offset + 37 + variable <= bytes.count else { return [] }
            result.append(BoardingWalletLeg(index: index, details: BoardingWalletDetails(passenger: passenger, origin: from, destination: to, seat: normalizedSeat(rawSeat) ?? "")))
            offset += 37 + variable
        }
        return result
    }

    static func declaredLegCount(barcode: BoardingWalletBarcode) -> Int {
        guard barcode.message.first == "M", let value = barcode.message.dropFirst().first, let count = Int(String(value)), (1...4).contains(count) else { return 0 }
        return count
    }

    static func suggestions(data: Data, mime: String, barcode: BoardingWalletBarcode, page: Int, legIndex: Int = 0) throws -> BoardingWalletDetails {
        guard data.count <= maximumBytes else { throw APIError.invalid("El pase supera los 10 MB.") }
        guard ["application/pdf", "image/jpeg", "image/png"].contains(mime) else { throw APIError.invalid("El archivo del pase no es compatible.") }
        try Task.checkCancellation()
        let choices = legs(barcode: barcode)
        let base = choices.first(where: { $0.index == legIndex })?.details ?? BoardingWalletDetails()
        // A page may show more than one leg. Only the selected BCBP leg is safe
        // without a spatial association between each label and that leg.
        guard (0..<declaredLegCount(barcode: barcode)).contains(legIndex), declaredLegCount(barcode: barcode) <= 1 else { return base }
        if mime == "application/pdf" {
            guard let document = PDFDocument(data: data), !document.isEncrypted, (1...12).contains(document.pageCount),
                  (1...document.pageCount).contains(page), let selected = document.page(at: page - 1) else {
                throw APIError.invalid("No se pudo leer esta página del pase.")
            }
            let text = String((selected.string ?? "").prefix(maximumText))
            let suggested = suggestions(text: text, barcode: barcode, legIndex: legIndex)
            // Embedded PDF text is preferred to OCR. A second reading can only
            // supply absent fields, never overwrite a clear embedded value.
            if !suggested.departureTime.isEmpty && !suggested.boardingTime.isEmpty { return suggested }
            let labels = collected(text)
            if ambiguousDocument(labels, base: base) { return base }
            guard let image = try pdfImage(data: data, page: page) else { return suggested }
            return try addingOCR(image, existing: suggested, barcode: barcode, legIndex: legIndex)
        }
        guard page == 1, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary),
              image.width * image.height <= 4_000_000 else { throw APIError.invalid("No se pudo leer la imagen del pase.") }
        return try addingOCR(image, existing: base, barcode: barcode, legIndex: legIndex)
    }

    /// The same deterministic interpretation is used for embedded PDF text and
    /// OCR, and is available to focused tests without running Vision models.
    static func suggestions(text: String, barcode: BoardingWalletBarcode, legIndex: Int = 0, allowFollowingLine: Bool = true) -> BoardingWalletDetails {
        let choices = legs(barcode: barcode)
        var details = choices.first(where: { $0.index == legIndex })?.details ?? BoardingWalletDetails()
        guard (0..<declaredLegCount(barcode: barcode)).contains(legIndex), declaredLegCount(barcode: barcode) <= 1 else { return details }
        let fields = collected(text, allowFollowingLine: allowFollowingLine)
        guard !ambiguousDocument(fields, base: details) else { return details }
        if let passenger = unique(fields[.passenger], transform: passengerValue), details.passenger.isEmpty || compatibleNames(details.passenger, passenger) { details.passenger = passenger }
        if details.origin.isEmpty, let origin = unique(fields[.origin], transform: routeValue) { details.origin = origin }
        if details.destination.isEmpty, let destination = unique(fields[.destination], transform: routeValue) { details.destination = destination }
        details.departureTime = unique(fields[.departureTime], transform: normalizedTime) ?? ""
        details.boardingTime = unique(fields[.boardingTime], transform: normalizedTime) ?? ""
        if details.seat.isEmpty { details.seat = unique(fields[.seat], transform: normalizedSeat) ?? "" }
        return details
    }

    private struct CardReading {
        let details: BoardingCardDetails
        let ambiguous: Bool
        let hasSeat: Bool
        let hasDeparture: Bool
        var fields: [Field: [String]] = [:]
    }
    /// A clear PDF does not need a compatible barcode for an informational
    /// card. Unlike Wallet, the card never transfers or creates a barcode.
    static func cardSuggestions(text: String, barcode: BoardingWalletBarcode? = nil, allowFollowingLine: Bool = true) -> BoardingCardDetails {
        cardReading(text: text, barcode: barcode, allowFollowingLine: allowFollowingLine).details
    }
    private static func cardReading(text: String, barcode: BoardingWalletBarcode?, allowFollowingLine: Bool = true) -> CardReading {
        var fields = collected(text, allowFollowingLine: allowFollowingLine)
        // The document's boarding time is deliberately irrelevant to this card.
        // Wallet's existing suggestions continue to retain that original value.
        fields[.boardingTime] = nil
        var base = BoardingWalletDetails()
        if let barcode {
            let choices = legs(barcode: barcode)
            guard declaredLegCount(barcode: barcode) == 1, choices.count == 1 else {
                return CardReading(details: BoardingCardDetails(), ambiguous: true, hasSeat: false, hasDeparture: false)
            }
            base = choices[0].details
        }
        let hasSeat = fields[.seat] != nil, hasDeparture = fields[.departureTime] != nil
        let conflictingSeats = (fields[.seat]?.count ?? 0) > 1 && unique(fields[.seat], transform: normalizedSeat) == nil
        guard text.count <= maximumText, !conflictingSeats, !ambiguousDocument(fields, base: base) else {
            return CardReading(details: BoardingCardDetails(), ambiguous: true, hasSeat: hasSeat, hasDeparture: hasDeparture)
        }
        let seat = hasSeat ? unique(fields[.seat], transform: normalizedSeat) ?? "" : base.seat
        return CardReading(details: BoardingCardDetails(seat: seat, departureTime: unique(fields[.departureTime], transform: normalizedTime) ?? ""), ambiguous: false, hasSeat: hasSeat, hasDeparture: hasDeparture, fields: fields)
    }

    static func cardDetails(data: Data, mime: String) throws -> BoardingCardDetails {
        guard data.count <= maximumBytes else { throw APIError.invalid("El pase supera los 10 MB.") }
        guard ["application/pdf", "image/jpeg", "image/png"].contains(mime) else { throw APIError.invalid("El archivo del pase no es compatible.") }
        try Task.checkCancellation()
        if mime == "application/pdf" {
            guard let document = PDFDocument(data: data), !document.isEncrypted, (1...12).contains(document.pageCount) else {
                throw APIError.invalid("No se pudo leer este PDF.")
            }
            let texts = (0..<document.pageCount).map { String((document.page(at: $0)?.string ?? "").prefix(maximumText + 1)) }
            let combined = texts.joined(separator: "\n")
            let whole = cardReading(text: combined, barcode: nil)
            guard !whole.ambiguous else { return BoardingCardDetails() }
            if document.pageCount == 1, !whole.details.seat.isEmpty, !whole.details.departureTime.isEmpty { return whole.details }
            var found: [(page: Int, barcode: BoardingWalletBarcode)] = []
            var detections = 0
            for page in 1...document.pageCount {
                try Task.checkCancellation()
                let codes = try autoreleasepool { () throws -> [BoardingWalletBarcode] in
                    guard let image = try pdfImage(data: data, page: page) else { return [] }
                    return try cardBarcodes(image, detections: &detections)
                }
                found += codes.map { (page, $0) }
            }
            let messages = Set(found.map { $0.barcode.message })
            guard messages.count <= 1 else { return BoardingCardDetails() }
            if let code = found.first?.barcode {
                guard declaredLegCount(barcode: code) == 1, legs(barcode: code).count == 1 else { return BoardingCardDetails() }
            }
            // Multiple pages can contain different passengers or flights. A
            // fallback uses only the one page holding the one identified flight;
            // it never combines a seat from one page with a time from another.
            let page: Int
            if document.pageCount == 1 { page = 1 }
            else {
                let pages = Set(found.map(\.page))
                guard messages.count == 1, pages.count == 1, let selected = pages.first else { return BoardingCardDetails() }
                page = selected
            }
            let reading = cardReading(text: texts[page - 1], barcode: found.first?.barcode)
            guard !reading.ambiguous else { return BoardingCardDetails() }
            if !reading.details.seat.isEmpty && !reading.details.departureTime.isEmpty { return reading.details }
            guard let image = try pdfImage(data: data, page: page) else { return reading.details }
            return try cardOCR(image, existing: reading, barcode: found.first?.barcode)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary),
              image.width * image.height <= 4_000_000 else { throw APIError.invalid("No se pudo leer la imagen del pase.") }
        var detections = 0
        let codes = try cardBarcodes(image, detections: &detections)
        guard Set(codes.map(\.message)).count <= 1 else { return BoardingCardDetails() }
        let reading = cardReading(text: "", barcode: codes.first)
        guard !reading.ambiguous else { return BoardingCardDetails() }
        return try cardOCR(image, existing: reading, barcode: codes.first)
    }
    private static func cardBarcodes(_ image: CGImage, detections: inout Int) throws -> [BoardingWalletBarcode] {
        try Task.checkCancellation()
        let request = VNDetectBarcodesRequest()
        try BoardingCodeExtractor.configure(request)
        request.symbologies = [.qr, .pdf417, .aztec]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try Task.checkCancellation()
        let observations = request.results ?? []
        detections += observations.count
        guard detections <= 24 else { throw APIError.invalid("Este documento contiene demasiados códigos.") }
        return observations.compactMap { BoardingWalletBarcode.extracted($0.symbology, message: $0.payloadStringValue) }
    }
    private static func cardOCR(_ image: CGImage, existing: CardReading, barcode: BoardingWalletBarcode?) throws -> BoardingCardDetails {
        try Task.checkCancellation()
        do {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.recognitionLanguages = ["es-ES", "en-US"]; request.usesLanguageCorrection = false; request.minimumTextHeight = 0.008
            try BoardingCodeExtractor.configure(request)
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            try Task.checkCancellation()
            let observations = (request.results ?? []).sorted { a, b in abs(a.boundingBox.midY - b.boundingBox.midY) > 0.018 ? a.boundingBox.midY > b.boundingBox.midY : a.boundingBox.minX < b.boundingBox.minX }
            let text = observations.prefix(256).compactMap { observation -> String? in
                guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.7 else { return nil }
                return String(candidate.string.prefix(160))
            }.joined(separator: "\n")
            let reading = cardReading(text: text, barcode: barcode, allowFollowingLine: false)
            guard !reading.ambiguous else { return BoardingCardDetails() }
            var combined = existing.fields
            for (field, values) in reading.fields { combined[field, default: []] += values }
            let base = barcode.flatMap { legs(barcode: $0).first?.details } ?? BoardingWalletDetails()
            let conflictingSeats = (combined[.seat]?.count ?? 0) > 1 && unique(combined[.seat], transform: normalizedSeat) == nil
            guard !conflictingSeats, !ambiguousDocument(combined, base: base) else { return BoardingCardDetails() }
            return BoardingCardDetails(seat: existing.hasSeat ? existing.details.seat : reading.details.seat.isEmpty ? existing.details.seat : reading.details.seat,
                                       departureTime: existing.hasDeparture ? existing.details.departureTime : reading.details.departureTime)
        } catch is CancellationError { throw CancellationError() }
        catch { return existing.details }
    }

    static func normalizedTime(_ value: String) -> String? {
        var text = folded(clean(value))
        text = text.replacingOccurrences(of: "([AP])\\s*\\.?\\s*M\\.?", with: "$1M", options: .regularExpression)
        guard let regex = try? NSRegularExpression(pattern: "^(\\d{1,2}):(\\d{2})\\s*(AM|PM)?$"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text), let minuteRange = Range(match.range(at: 2), in: text),
              var hour = Int(text[hourRange]), let minute = Int(text[minuteRange]), (0...59).contains(minute) else { return nil }
        if let periodRange = Range(match.range(at: 3), in: text) {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (text[periodRange] == "PM" ? 12 : 0)
        } else if !(0...23).contains(hour) { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func normalizedSeat(_ value: String) -> String? {
        let seat = clean(value).uppercased().replacingOccurrences(of: "^0+(?=[0-9])", with: "", options: .regularExpression)
        guard matches(seat, "^[0-9]{1,3}[A-Z]?$"), !matches(seat, "^0+[A-Z]?$") else { return nil }
        return seat
    }
    private static func passengerValue(_ value: String) -> String? {
        let text = clean(value)
        guard (2...120).contains(text.count), matches(text, "^[\\p{L}][\\p{L}\\p{M} .’'/-]*$") else { return nil }
        return text
    }
    private static func routeValue(_ value: String) -> String? {
        let text = clean(value)
        guard (2...100).contains(text.count), matches(text, "^[\\p{L}][\\p{L}\\p{M} .’'()/-]*$") else { return nil }
        if let regex = try? NSRegularExpression(pattern: "\\(([A-Z]{3})\\)"), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) { return String(text[range]) }
        return text
    }
    private static func compatibleNames(_ first: String, _ second: String) -> Bool {
        let a = folded(first).split(whereSeparator: { !$0.isLetter }).map(String.init)
        let b = folded(second).split(whereSeparator: { !$0.isLetter }).map(String.init)
        if a == b { return true }
        return a.count >= 2 && a.allSatisfy { token in token.count >= 2 && b.contains(where: { $0.hasPrefix(token) || token.hasPrefix($0) }) }
    }
    private static func folded(_ value: String) -> String { value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CO")).uppercased() }
    private static func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":|–—"))).replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression) }
    private static func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    private static func unique(_ values: [String]?, transform: (String) -> String?) -> String? {
        guard let values, !values.isEmpty else { return nil }
        let parsed = values.map(transform)
        guard parsed.allSatisfy({ $0 != nil }) else { return nil }
        let distinct = Set(parsed.compactMap { $0 })
        return distinct.count == 1 ? distinct.first : nil
    }
    private static func ambiguousDocument(_ fields: [Field: [String]], base: BoardingWalletDetails) -> Bool {
        for field in [Field.passenger, .origin, .destination] {
            guard let values = fields[field], !values.isEmpty else { continue }
            if Set(values.map { folded(clean($0)) }).count > 1 { return true }
        }
        if let passenger = unique(fields[.passenger], transform: passengerValue), !base.passenger.isEmpty, !compatibleNames(base.passenger, passenger) { return true }
        for (field, expected) in [(Field.origin, base.origin), (.destination, base.destination)] where !expected.isEmpty {
            if let raw = unique(fields[field], transform: routeValue), matches(raw, "^[A-Z]{3}$"), raw != expected { return true }
        }
        for field in [Field.departureTime, .boardingTime] {
            if let values = fields[field], values.count > 1, unique(values, transform: normalizedTime) == nil { return true }
            if fields[field]?.contains(where: { value in
                guard let regex = try? NSRegularExpression(pattern: "[0-9]{1,2}:[0-9]{2}") else { return false }
                return regex.numberOfMatches(in: value, range: NSRange(value.startIndex..., in: value)) > 1
            }) == true { return true }
        }
        return false
    }
    private static func collected(_ text: String, allowFollowingLine: Bool = true) -> [Field: [String]] {
        let lines = String(text.prefix(maximumText)).precomposedStringWithCanonicalMapping.components(separatedBy: .newlines).map(clean).filter { !$0.isEmpty }
        var fields: [Field: [String]] = [:]
        for (lineIndex, line) in lines.enumerated() {
            var labels: [(field: Field, range: NSRange)] = []
            for (field, pattern) in labelPatterns {
                guard let regex = try? NSRegularExpression(pattern: "(?<![A-Z])(?:" + pattern + ")(?![A-Z])", options: .caseInsensitive) else { continue }
                for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                    // Longer compound labels take priority over e.g. SALIDA,
                    // PASSENGER, SALA or FLIGHT inside the same label.
                    if !labels.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) { labels.append((field, match.range)) }
                }
            }
            labels.sort { $0.range.location < $1.range.location }
            for (index, label) in labels.enumerated() where label.field != .stop {
                let start = NSMaxRange(label.range), end = index + 1 < labels.count ? labels[index + 1].range.location : (line as NSString).length
                guard start <= end, let range = Range(NSRange(location: start, length: end - start), in: line) else { continue }
                var value = clean(String(line[range]))
                if value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "/-:|–—"))).isEmpty { value = "" }
                if value.isEmpty && allowFollowingLine && labels.count == 1 && lineIndex + 1 < lines.count {
                    let next = lines[lineIndex + 1]
                    let nextHasLabel = labelPatterns.contains { _, pattern in
                        next.range(of: "(?<![A-Z])(?:" + pattern + ")(?![A-Z])", options: [.regularExpression, .caseInsensitive]) != nil
                    }
                    let previousIsBareLabel = lineIndex > 0 && labelPatterns.contains { _, pattern in
                        lines[lineIndex - 1].range(of: "^(?:" + pattern + ")\\s*[:|–—-]?\\s*$", options: [.regularExpression, .caseInsensitive]) != nil
                    }
                    if !nextHasLabel && !previousIsBareLabel { value = next }
                }
                guard !value.isEmpty, value.count <= 160, !value.unicodeScalars.contains(where: { $0.value < 32 || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) }) else { continue }
                fields[label.field, default: []].append(value)
            }
        }
        return fields
    }

    private static func addingOCR(_ image: CGImage, existing: BoardingWalletDetails, barcode: BoardingWalletBarcode, legIndex: Int) throws -> BoardingWalletDetails {
        try Task.checkCancellation()
        do {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.recognitionLanguages = ["es-ES", "en-US"]; request.usesLanguageCorrection = false; request.minimumTextHeight = 0.008
            try BoardingCodeExtractor.configure(request)
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            try Task.checkCancellation()
            let observations = (request.results ?? []).sorted { a, b in abs(a.boundingBox.midY - b.boundingBox.midY) > 0.018 ? a.boundingBox.midY > b.boundingBox.midY : a.boundingBox.minX < b.boundingBox.minX }
            let text = observations.prefix(256).compactMap { observation -> String? in guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.7 else { return nil }; return String(candidate.string.prefix(160)) }.joined(separator: "\n")
            // Vision observations from separate columns have no stable text
            // reading order. Only a label and value within the same recognized
            // line are associated; standalone OCR headers stay for manual entry.
            let fallback = suggestions(text: text, barcode: barcode, legIndex: legIndex, allowFollowingLine: false)
            return BoardingWalletDetails(passenger: existing.passenger.isEmpty ? fallback.passenger : existing.passenger, origin: existing.origin.isEmpty ? fallback.origin : existing.origin, destination: existing.destination.isEmpty ? fallback.destination : existing.destination, departureTime: existing.departureTime.isEmpty ? fallback.departureTime : existing.departureTime, boardingTime: existing.boardingTime.isEmpty ? fallback.boardingTime : existing.boardingTime, seat: existing.seat.isEmpty ? fallback.seat : existing.seat)
        } catch is CancellationError { throw CancellationError() }
        catch { return existing }
    }
    private static func pdfImage(data: Data, page number: Int) throws -> CGImage? {
        try Task.checkCancellation()
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider), !document.isEncrypted,
              (1...12).contains(document.numberOfPages), let page = document.page(at: number) else { return nil }
        let box = page.getBoxRect(.cropBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { return nil }
        let rotated = abs(page.rotationAngle) % 180 == 90
        let w = rotated ? box.height : box.width, h = rotated ? box.width : box.height, scale = 1600 / max(w, h)
        let width = max(1, Int((w * scale).rounded())), height = max(1, Int((h * scale).rounded()))
        guard width * height <= 4_000_000, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true)); context.drawPDFPage(page)
        return context.makeImage()
    }
}
