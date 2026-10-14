import SwiftUI

/// The hearts in the air on one card. The card draws them with `KissLayer`.
/// A heart the person sends flies from their avatar to the partner's. A heart the
/// partner sent flies back. A cap keeps rapid tapping and big bursts bounded.
@MainActor
@Observable
final class HeartFlights {
    private(set) var kisses: [TapKiss] = []

    /// Hearts in the air at once. The oldest goes first when a new one starts.
    static let maxConcurrent = 24
    /// Gap between the hearts of a burst, so they leave one after another.
    private static let burstSpacing: TimeInterval = 0.14

    /// A heart from the person to the partner, in the air right away.
    func send() {
        launch(forward: true, after: 0)
    }

    /// `count` hearts from the partner to the person, one after another.
    func receive(count: Int) {
        for index in 0..<count {
            let jitter = Double.random(in: 0..<Self.burstSpacing)
            launch(forward: false, after: Double(index) * Self.burstSpacing + jitter)
        }
    }

    private func launch(forward: Bool, after delay: TimeInterval) {
        if kisses.count >= Self.maxConcurrent {
            kisses.removeFirst()
        }
        let kiss = TapKiss(
            bornAt: .now.addingTimeInterval(delay),
            plan: KissPlan(forward: forward, next: { Double.random(in: 0..<1) })
        )
        kisses.append(kiss)

        // Drop it once its flight is over so the array returns to empty.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay + kiss.plan.flightDuration + 0.2))
            self?.kisses.removeAll { $0.id == kiss.id }
        }
    }
}
