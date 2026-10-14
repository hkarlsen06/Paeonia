import Foundation
import PencilKit
@testable import PaeoniaApp

// Small pieces the two-phone Draw & Guess simulation shares: the seeded random
// numbers, the simulated clock, and the action log printed on a failure.

/// SplitMix64. The seed decides every choice the driver and the faults make.
struct SimRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// A number in `0..<1`.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[Int(next() % UInt64(items.count))]
    }

    /// Picks by weight. Weights of zero never win.
    mutating func weighted<T>(_ items: [(T, Double)]) -> T {
        let total = items.reduce(0) { $0 + $1.1 }
        var roll = unit() * total
        for (item, weight) in items where weight > 0 {
            roll -= weight
            if roll < 0 { return item }
        }
        return items.last { $0.1 > 0 }?.0 ?? items[0].0
    }

    /// A new generator for a part of the simulation, so its draws do not shift
    /// the driver's when that part runs a different number of times.
    mutating func split() -> SimRandom {
        SimRandom(seed: next())
    }
}

/// The time both phones and the server read. It moves only when the driver moves it.
final class SimClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// What happened, in order. Printed with the seed when an invariant breaks.
@MainActor
final class SimLog {
    private(set) var lines: [String] = []
    var step = 0

    func add(_ line: String) {
        lines.append("[\(step)] \(line)")
    }

    func tail(_ count: Int = 400) -> String {
        lines.suffix(count).joined(separator: "\n")
    }
}

/// An invariant the simulation found broken.
struct SimFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// The phone's operations, with one client id per phone and a sequence that
/// survives a force quit, as `SyncClientOperationFactory` keeps it in defaults.
@MainActor
final class SimOperationProvider: SyncClientOperationProviding {
    private let clientID = UUID()
    private var sequence: Int64 = 0
    private let clock: SimClock

    init(clock: SimClock) {
        self.clock = clock
    }

    func makeOperation() -> SyncClientOperation {
        sequence += 1
        return SyncClientOperation(clientID: clientID, clientSequence: sequence, localCreatedAt: clock.now)
    }
}

/// Strokes for the drawer, made the way PencilKit makes them: points with time
/// offsets, on a canvas of `side` points.
enum SimStrokes {
    /// Gives every stroke its own creation time, which is part of its live key.
    nonisolated(unsafe) private static var created = Date().timeIntervalSinceReferenceDate

    static func stroke(seed: inout SimRandom, side: CGFloat) -> PKStroke {
        let count = seed.int(3...8)
        var x = CGFloat(seed.unit()) * side * 0.8 + side * 0.1
        var y = CGFloat(seed.unit()) * side * 0.8 + side * 0.1
        var points: [PKStrokePoint] = []
        for index in 0..<count {
            points.append(PKStrokePoint(
                location: CGPoint(x: x, y: y),
                timeOffset: TimeInterval(index) * 0.03,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ))
            x = min(side - 2, max(2, x + CGFloat(seed.unit() - 0.5) * 40))
            y = min(side - 2, max(2, y + CGFloat(seed.unit() - 0.5) * 40))
        }
        created += 0.05
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: created))
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }
}

/// Where a run reports, and the watchdog that stops a seed that hangs.
@MainActor
enum SimReport {
    /// Appends to `path` on the Mac, which the simulator can write.
    nonisolated static func write(_ text: String, to path: String = "/tmp/dng-sim.log") {
        let url = URL(fileURLWithPath: path)
        let line = Data((text + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    /// Runs `body`, and gives up on it after `timeout` instead of hanging the suite.
    static func run(timeout: Duration, _ body: @escaping @MainActor () async throws -> Void) async throws {
        let outcome = AsyncStream<Error?>.makeStream()
        let work = Task { @MainActor in
            do {
                try await body()
                outcome.continuation.yield(nil)
            } catch {
                outcome.continuation.yield(error)
            }
        }
        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            outcome.continuation.yield(SimFailure(message: "hung for \(timeout)"))
        }
        defer {
            watchdog.cancel()
            work.cancel()
        }
        for await result in outcome.stream {
            if let result { throw result }
            return
        }
    }
}
