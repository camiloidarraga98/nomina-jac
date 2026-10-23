import XCTest
import CoreGraphics
import CoreText
#if os(iOS)
@testable import JACNomina
#else
@testable import JACMac
#endif

final class BoardingWalletDetailsTests: XCTestCase {
    private func leg(_ origin: String, _ destination: String, seat: String, extra: String = "") -> String {
        "ABC123 " + origin + destination + "ZZ " + "00001" + "297" + "Y" + seat + "00001" + "1" + String(format: "%02X", extra.utf8.count) + extra
    }
    private func barcode(_ segments: [String]) throws -> BoardingWalletBarcode {
        let message = "M\(segments.count)" + "TRAVELLER/FIXTURE".padding(toLength: 20, withPad: " ", startingAt: 0) + "E" + segments.joined() + "   "
        return try XCTUnwrap(BoardingWalletBarcode(format: "PKBarcodeFormatQR", message: message))
    }

    func testBCBPLegsKeepTheirOwnRouteAndSeatWithoutChangingTheBarcode() throws {
        let code = try barcode([leg("BOG", "MDE", seat: "012A", extra: "ABCD"), leg("MDE", "CLO", seat: "022C")])
        let original = code.message, result = BoardingWalletDetailsExtractor.legs(barcode: code)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.index), [0, 1])
        XCTAssertEqual(result.map { $0.details.passenger }, ["FIXTURE TRAVELLER", "FIXTURE TRAVELLER"])
        XCTAssertEqual(result.map { $0.details.origin }, ["BOG", "MDE"])
        XCTAssertEqual(result.map { $0.details.destination }, ["MDE", "CLO"])
        XCTAssertEqual(result.map { $0.details.seat }, ["12A", "22C"])
        XCTAssertEqual(code.message, original)
        var unnamed = Array(original.utf8)
        unnamed.replaceSubrange(2..<22, with: repeatElement(UInt8(32), count: 20))
        let missingName = try XCTUnwrap(BoardingWalletBarcode(format: "PKBarcodeFormatQR", message: String(decoding: unnamed, as: UTF8.self)))
        let unnamedLegs = BoardingWalletDetailsExtractor.legs(barcode: missingName)
        XCTAssertEqual(unnamedLegs.map { $0.details.origin }, ["BOG", "MDE"])
        XCTAssertTrue(unnamedLegs.allSatisfy { $0.details.passenger.isEmpty }, "A missing passenger name must be completed, not substituted with the JAC account.")
        var damaged = Array(original.utf8)
        damaged[23 + 37 + 4 + 7] = 48
        let invalid = try XCTUnwrap(BoardingWalletBarcode(format: "PKBarcodeFormatQR", message: String(decoding: damaged, as: UTF8.self)))
        XCTAssertTrue(BoardingWalletDetailsExtractor.legs(barcode: invalid).isEmpty, "Do not return a partly parsed multi-leg journey.")
    }

    func testDocumentLabelsReadFlightAndBoardingTimesWithoutUsingArrivalOrGate() throws {
        let code = try barcode([leg("BOG", "MDE", seat: "0000")])
        let text = """
        BOARDING PASS
        PASAJERO / PASSENGER: FIXTURE TRAVELLER
        ORIGEN: BOG
        DESTINO: MDE
        HORA DEL VUELO: 6:45 p. m.
        HORA EN SALA: 6:05 PM
        LLEGADA: 19:40
        PUERTA: 8
        SILLA: 012A
        """
        let result = BoardingWalletDetailsExtractor.suggestions(text: text, barcode: code)
        XCTAssertEqual(result.passenger, "FIXTURE TRAVELLER")
        XCTAssertEqual(result.departureTime, "18:45")
        XCTAssertEqual(result.boardingTime, "18:05")
        XCTAssertEqual(result.seat, "12A")
        XCTAssertEqual(BoardingWalletDetailsExtractor.normalizedTime("12:05 AM"), "00:05")
        XCTAssertEqual(BoardingWalletDetailsExtractor.normalizedTime("12:05 PM"), "12:05")
        for unknown in ["24:00", "14:61", "00:30 AM", "18:45 / 19:45", "Gate 6", "18:45 UTC-5"] {
            XCTAssertNil(BoardingWalletDetailsExtractor.normalizedTime(unknown))
        }
        let missing = BoardingWalletDetailsExtractor.suggestions(text: "ARRIVAL: 19:40\nGATE: 8\nASIENTO: SIN ASIGNAR", barcode: code)
        XCTAssertTrue(missing.departureTime.isEmpty)
        XCTAssertTrue(missing.boardingTime.isEmpty)
        XCTAssertTrue(missing.seat.isEmpty)
    }

    func testAmbiguousPeopleLegsAndHoursNeverSupplyAnotherFlightInformation() throws {
        let single = try barcode([leg("BOG", "MDE", seat: "012A")])
        for text in [
            "PASSENGER: FIXTURE TRAVELLER\nPASSENGER: ANOTHER PERSON\nDEPARTURE: 18:45\nBOARDING: 18:05",
            "FROM: CLO\nTO: BOG\nDEPARTURE: 18:45\nBOARDING: 18:05",
            "DEPARTURE: 06:00\nDEPARTURE: 18:45\nBOARDING: 18:05"
        ] {
            let result = BoardingWalletDetailsExtractor.suggestions(text: text, barcode: single)
            XCTAssertEqual(result.origin, "BOG"); XCTAssertEqual(result.destination, "MDE")
            XCTAssertEqual(result.seat, "12A"); XCTAssertTrue(result.departureTime.isEmpty); XCTAssertTrue(result.boardingTime.isEmpty)
        }
        let multiple = try barcode([leg("BOG", "MDE", seat: "012A"), leg("MDE", "CLO", seat: "022C")])
        let selected = BoardingWalletDetailsExtractor.suggestions(text: "DEPARTURE: 06:00\nBOARDING: 05:20", barcode: multiple, legIndex: 1)
        XCTAssertEqual(selected.origin, "MDE"); XCTAssertEqual(selected.destination, "CLO"); XCTAssertEqual(selected.seat, "22C")
        XCTAssertTrue(selected.departureTime.isEmpty); XCTAssertTrue(selected.boardingTime.isEmpty)
        let unknownMultiple = try XCTUnwrap(BoardingWalletBarcode(format: "PKBarcodeFormatQR", message: "M2" + String(repeating: "A", count: 58)))
        let unidentified = BoardingWalletDetailsExtractor.suggestions(text: "FROM: BOG\nTO: MDE\nDEPARTURE: 06:00\nBOARDING: 05:20", barcode: unknownMultiple, legIndex: 1)
        XCTAssertEqual(BoardingWalletDetailsExtractor.declaredLegCount(barcode: unknownMultiple), 2)
        XCTAssertEqual(unidentified, BoardingWalletDetails(), "Unknown multi-leg structure must be completed explicitly instead of using another leg's text.")
    }

    func testTextRangesAndSeparateOCRColumnsCannotShiftOrSwapTimes() throws {
        let code = try barcode([leg("BOG", "MDE", seat: "012A")])
        let original = BoardingWalletDetailsExtractor.suggestions(text: "PASAJERO: Groß/Foo HORA DE SALIDA: 10:30\nBOARDING: 10:00", barcode: code)
        XCTAssertTrue(original.departureTime.isEmpty, "A different passenger cannot supply times.")
        let unknown = try XCTUnwrap(BoardingWalletBarcode(format: "PKBarcodeFormatQR", message: "M1" + String(repeating: "A", count: 58)))
        let unicode = BoardingWalletDetailsExtractor.suggestions(text: "PASAJERO: Groß/Foo HORA DE SALIDA: 10:30", barcode: unknown)
        XCTAssertEqual(unicode.departureTime, "10:30", "Ranges must refer to the original Unicode line.")
        let columns = "DEPARTURE\nBOARDING\n18:45\n18:05"
        for allowNextLine in [false, true] {
            let result = BoardingWalletDetailsExtractor.suggestions(text: columns, barcode: code, allowFollowingLine: allowNextLine)
            XCTAssertTrue(result.departureTime.isEmpty); XCTAssertTrue(result.boardingTime.isEmpty)
        }
        let inlineOCR = BoardingWalletDetailsExtractor.suggestions(text: "DEPARTURE 18:45\nBOARDING 18:05", barcode: code, allowFollowingLine: false)
        XCTAssertEqual(inlineOCR.departureTime, "18:45"); XCTAssertEqual(inlineOCR.boardingTime, "18:05")
        let verticalPDF = BoardingWalletDetailsExtractor.suggestions(text: "DEPARTURE\n18:45\nBOARDING\n18:05", barcode: code)
        XCTAssertEqual(verticalPDF.departureTime, "18:45"); XCTAssertEqual(verticalPDF.boardingTime, "18:05")
    }

    func testPDFSuggestionsUseOnlyThePageContainingTheChosenCode() throws {
        let code = try barcode([leg("MDE", "CLO", seat: "022C")])
        let data = try pdf([
            ["PASAJERO: ANOTHER PERSON", "ORIGEN: BOG", "DESTINO: MDE", "HORA DEL VUELO: 06:15", "HORA EN SALA: 05:40"],
            ["PASAJERO: FIXTURE TRAVELLER", "ORIGEN: MDE", "DESTINO: CLO", "HORA DEL VUELO: 21:10", "HORA EN SALA: 20:25", "SILLA: 22C"]
        ])
        let selected = try BoardingWalletDetailsExtractor.suggestions(data: data, mime: "application/pdf", barcode: code, page: 2)
        XCTAssertEqual(selected.passenger, "FIXTURE TRAVELLER")
        XCTAssertEqual(selected.origin, "MDE"); XCTAssertEqual(selected.destination, "CLO")
        XCTAssertEqual(selected.departureTime, "21:10"); XCTAssertEqual(selected.boardingTime, "20:25"); XCTAssertEqual(selected.seat, "22C")
    }

    private func pdf(_ pages: [[String]]) throws -> Data {
        let data = NSMutableData(), consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
        for lines in pages {
            context.beginPDFPage(nil)
            for (index, text) in lines.enumerated() {
                let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                context.textPosition = CGPoint(x: 40, y: CGFloat(740 - index * 30))
                CTLineDraw(CTLineCreateWithAttributedString(attributed as CFAttributedString), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
