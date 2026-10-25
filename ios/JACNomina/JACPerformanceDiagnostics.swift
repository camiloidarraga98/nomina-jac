import Foundation
import OSLog

// Counts actual expensive operations, not view reevaluations. Keep diagnostics
// outside ObservableObject so collecting a sample never invalidates the UI.
enum JACPerformanceDiagnostics {
    enum Operation: Int, CaseIterable { case diskRead, diskWrite, indexWrite, keyDerivation, jsonDecode, jsonEncode, sessionRead }
    struct Snapshot {
        fileprivate let total: [Int: Int]
        fileprivate let main: [Int: Int]
        func count(_ operation: Operation, mainThread: Bool = false) -> Int { (mainThread ? main : total)[operation.rawValue, default: 0] }
        func delta(from earlier: Snapshot) -> Snapshot {
            Snapshot(total: Dictionary(uniqueKeysWithValues: Operation.allCases.map { ($0.rawValue, count($0) - earlier.count($0)) }),
                     main: Dictionary(uniqueKeysWithValues: Operation.allCases.map { ($0.rawValue, count($0, mainThread: true) - earlier.count($0, mainThread: true)) }))
        }
        var mainThreadExpensiveOperations: Int { [Operation.diskRead, .diskWrite, .keyDerivation, .jsonDecode, .jsonEncode, .sessionRead].reduce(0) { $0 + count($1, mainThread: true) } }
    }
    #if DEBUG
    private final class Counters: @unchecked Sendable {
        let lock = NSLock()
        var total: [Int: Int] = [:]
        var main: [Int: Int] = [:]
    }
    private static let counters = Counters()
    private static let logger = Logger(subsystem: "co.jacmusic.nomina", category: "ScrollPerformance")
    #endif
    static func record(_ operation: Operation) {
        #if DEBUG
        let onMain = Thread.isMainThread
        counters.lock.lock(); defer { counters.lock.unlock() }
        counters.total[operation.rawValue, default: 0] += 1
        if onMain { counters.main[operation.rawValue, default: 0] += 1 }
        #endif
    }
    static func snapshot() -> Snapshot {
        #if DEBUG
        counters.lock.lock(); defer { counters.lock.unlock() }
        return Snapshot(total: counters.total, main: counters.main)
        #else
        return Snapshot(total: [:], main: [:])
        #endif
    }
    static func reset() {
        #if DEBUG
        counters.lock.lock(); defer { counters.lock.unlock() }
        counters.total = [:]; counters.main = [:]
        #endif
    }
    // Explicitly called around a warmed scroll/render interval. No identifiers,
    // URLs, session markers, names, tokens or document content enter the log.
    static func reportHotPath(since previous: Snapshot) {
        #if DEBUG
        let sample = snapshot().delta(from: previous)
        if sample.mainThreadExpensiveOperations > 0 {
            logger.warning("Warm scroll work: main disk reads=\(sample.count(.diskRead, mainThread: true)) writes=\(sample.count(.diskWrite, mainThread: true)) key derivations=\(sample.count(.keyDerivation, mainThread: true)) JSON decodes=\(sample.count(.jsonDecode, mainThread: true))")
        }
        #endif
    }
}
