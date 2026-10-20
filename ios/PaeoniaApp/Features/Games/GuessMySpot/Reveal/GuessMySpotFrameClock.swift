import QuartzCore

/// Wakes the reveal's moves once a frame, in time with the screen. A 16 ms sleep
/// drifts against the display, so some frames got two steps and some none, which
/// showed as small hitches, and each move woke on its own. Every move waiting here
/// wakes in the same frame and reads the same time.
@MainActor
final class GuessMySpotFrameClock: NSObject {
    private static let shared = GuessMySpotFrameClock()

    private var waiting: [CheckedContinuation<CFTimeInterval, Never>] = []
    private var link: CADisplayLink?

    /// Returns at the next frame with the time it shows, on `CACurrentMediaTime`'s clock.
    static func nextFrame() async -> CFTimeInterval {
        await withCheckedContinuation { continuation in
            shared.waiting.append(continuation)
            shared.wake()
        }
    }

    private func wake() {
        if let link {
            link.isPaused = false
            return
        }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let ready = waiting
        waiting = []
        // Nothing moves, so the link sleeps until a move waits again.
        guard !ready.isEmpty else {
            link.isPaused = true
            return
        }
        ready.forEach { $0.resume(returning: link.targetTimestamp) }
    }
}
