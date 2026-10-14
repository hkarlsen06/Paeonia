import SwiftUI

/// Shape of one heart's flight. Every value is drawn independently from the given
/// random source, so no two kisses share a path, speed, size, or wobble. The same
/// plan type drives both the ambient kisses (fed a deterministic per-slot sequence)
/// and the tap-spawned ones (fed the system RNG).
struct KissPlan {
    let forward: Bool
    let flightDuration: Double
    let arcSign: CGFloat
    let arcMagnitude: CGFloat
    let loopTurns: CGFloat
    let loopSign: CGFloat
    let loopPhase: CGFloat
    let loopRadiusFactor: CGFloat
    let baseScale: CGFloat
    let rotationAmplitude: Double

    init(forward: Bool, next: () -> Double) {
        self.forward = forward
        // Slow, wind-like drift; speed varies kiss to kiss.
        flightDuration = 3.6 + next() * 3.0
        arcSign = next() < 0.5 ? -1 : 1
        arcMagnitude = 0.05 + CGFloat(next()) * 0.13
        loopPhase = CGFloat(next() * 2 * .pi)
        loopSign = next() < 0.5 ? -1 : 1

        // Only some kisses loop; the ones that do use 2-3 tighter turns of varying
        // size so the loops stay small while still crossing themselves.
        let hasLoop = next() < 0.6
        loopTurns = hasLoop ? (next() < 0.5 ? 2 : 3) : 0
        loopRadiusFactor = hasLoop ? (0.09 + CGFloat(next()) * 0.06) : 0

        baseScale = 0.8 + CGFloat(next()) * 0.5
        rotationAmplitude = 6 + next() * 10
    }
}

/// One tap-spawned heart in flight.
struct TapKiss: Identifiable {
    let id = UUID()
    let bornAt: Date
    let plan: KissPlan
}

/// Pure math for a heart's flight: a lightly arced path with optional enveloped
/// loops, plus fade and scale, computed for a 0...1 progress value.
enum KissMath {
    struct State {
        var position: CGPoint
        var opacity: Double
        var scale: CGFloat
        var rotation: Double
    }

    static func state(plan: KissPlan, start: CGPoint, end: CGPoint, progress: CGFloat) -> State {
        let from = plan.forward ? start : end
        let to = plan.forward ? end : start
        // Smootherstep eases the travel so it leaves one avatar and settles into the
        // other instead of moving at a constant clip.
        let along = smootherstep(progress)
        let (position, theta) = point(plan: plan, from: from, to: to, along: along)
        return State(
            position: position,
            opacity: fadeOpacity(progress),
            scale: scale(progress) * plan.baseScale,
            rotation: Double(sin(theta)) * plan.rotationAmplitude
        )
    }

    /// The loop radius grows enough mid-flight that the heart briefly backtracks,
    /// making real loops, and the envelope fades it to zero at both avatars for a
    /// clean launch and landing.
    private static func point(plan: KissPlan, from: CGPoint, to: CGPoint, along: CGFloat) -> (CGPoint, CGFloat) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = max(hypot(dx, dy), 1)

        let perpX = -dy / distance
        let perpY = dx / distance

        let envelope = sin(.pi * along)
        let arc = plan.arcSign * distance * plan.arcMagnitude * envelope
        let loopRadius = distance * plan.loopRadiusFactor * envelope
        let theta = plan.loopSign * 2 * .pi * plan.loopTurns * along + plan.loopPhase

        let computed = CGPoint(
            x: from.x + dx * along + perpX * arc + cos(theta) * loopRadius,
            y: from.y + dy * along + perpY * arc + sin(theta) * loopRadius
        )
        return (computed, theta)
    }

    private static func fadeOpacity(_ progress: CGFloat) -> Double {
        let fadeIn = min(progress / 0.18, 1)
        let fadeOut = min((1 - progress) / 0.18, 1)
        return Double(max(min(fadeIn, fadeOut), 0))
    }

    private static func scale(_ progress: CGFloat) -> CGFloat {
        if progress < 0.15 {
            return 0.6 + (progress / 0.15) * 0.4
        }
        if progress > 0.85 {
            return 1 + ((progress - 0.85) / 0.15) * 0.2
        }
        return 1
    }

    private static func smootherstep(_ progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * clamped * (clamped * (clamped * 6 - 15) + 10)
    }

    /// A stateless splitmix64-style hash mapped to 0..<1, so randomness is
    /// reproducible from a seed alone.
    static func random01(_ seed: Int) -> Double {
        var x = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x = x ^ (x >> 31)
        return Double(x >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// A deterministic sequence of pseudo-random values from one seed, for the
    /// ambient kiss (recomputed every frame, so it must be reproducible per slot).
    static func hashedSequence(seed: Int) -> () -> Double {
        var index = 0
        return {
            let value = random01(seed &+ index)
            index += 1
            return value
        }
    }
}

/// Draws every blown heart, the low-frequency ambient kiss plus any tap-spawned
/// ones, in a single timeline so there is just one display-link driver. Hidden
/// under Reduce Motion. The timeline pauses whenever no heart is in flight, so the
/// card does not redraw every frame while it sits idle.
struct KissLayer: View {
    let start: CGPoint
    let end: CGPoint
    let tapKisses: [TapKiss]
    /// Whether the low-frequency ambient heart drifts between the avatars too. The
    /// small heart row leaves it out.
    var showsAmbient = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True while the ambient heart is inside (or just around) its flight window.
    @State private var ambientActive = false

    /// Length of each ambient scheduling slot. The kiss happens at a random moment
    /// inside its slot, so the gap between kisses keeps shifting.
    private static let slotPeriod: TimeInterval = 16
    /// The timeline starts this long before the ambient heart appears and stops this
    /// long after it fades out, so a late wake-up never clips the first or last frame.
    private static let wakeMargin: TimeInterval = 0.1

    private var isIdle: Bool {
        tapKisses.isEmpty && !ambientActive
    }

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: nil, paused: isIdle)) { context in
                let now = context.date
                ZStack {
                    if showsAmbient, let state = ambientState(at: now) {
                        heart(state)
                    }
                    ForEach(tapKisses) { kiss in
                        if let state = tapState(kiss, at: now) {
                            heart(state)
                        }
                    }
                }
            }
            .task {
                if showsAmbient { await trackAmbientWindow() }
            }
        }
    }

    private func heart(_ state: KissMath.State) -> some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.paeoniaAccentSecondary)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .rotationEffect(.degrees(state.rotation))
            .scaleEffect(state.scale)
            .opacity(state.opacity)
            .position(state.position)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// One ambient flight, derived only from its slot number so the timeline, the
    /// frame math, and the pause scheduler all agree on when the heart is in the air.
    private struct AmbientFlight {
        let plan: KissPlan
        /// Seconds since the reference date at which the slot begins.
        let slotStart: TimeInterval
        /// Seconds into the slot at which the heart launches.
        let startOffset: TimeInterval

        var start: TimeInterval { slotStart + startOffset }
        var end: TimeInterval { start + plan.flightDuration }
    }

    private static func ambientFlight(slot: Int) -> AmbientFlight {
        let plan = KissPlan(
            forward: slot.isMultiple(of: 2),
            next: KissMath.hashedSequence(seed: slot &* 31)
        )
        let startOffset = KissMath.random01(slot &* 31 &- 1) * (slotPeriod - plan.flightDuration)
        return AmbientFlight(plan: plan, slotStart: Double(slot) * slotPeriod, startOffset: startOffset)
    }

    private func ambientState(at date: Date) -> KissMath.State? {
        let time = date.timeIntervalSinceReferenceDate
        let flight = Self.ambientFlight(slot: Int(floor(time / Self.slotPeriod)))
        let phase = time - flight.slotStart

        guard phase >= flight.startOffset, phase < flight.startOffset + flight.plan.flightDuration else {
            return nil
        }
        let progress = CGFloat((phase - flight.startOffset) / flight.plan.flightDuration)
        return KissMath.state(plan: flight.plan, start: start, end: end, progress: progress)
    }

    private func tapState(_ kiss: TapKiss, at date: Date) -> KissMath.State? {
        let elapsed = date.timeIntervalSince(kiss.bornAt)
        guard elapsed >= 0, elapsed <= kiss.plan.flightDuration else {
            return nil
        }
        let progress = CGFloat(elapsed / kiss.plan.flightDuration)
        return KissMath.state(plan: kiss.plan, start: start, end: end, progress: progress)
    }

    /// Flips `ambientActive` on at each ambient flight and off after it, sleeping
    /// between the boundaries. Ends when the task is cancelled.
    private func trackAmbientWindow() async {
        ambientActive = false
        do {
            while true {
                let now = Date.now.timeIntervalSinceReferenceDate
                var slot = Int(floor(now / Self.slotPeriod))
                var flight = Self.ambientFlight(slot: slot)
                // The current slot's flight may be over already; the next one is always ahead.
                while flight.end + Self.wakeMargin <= now {
                    slot += 1
                    flight = Self.ambientFlight(slot: slot)
                }

                let wakeAt = flight.start - Self.wakeMargin
                if now < wakeAt {
                    ambientActive = false
                    try await Self.sleep(untilReferenceTime: wakeAt)
                }
                ambientActive = true
                try await Self.sleep(untilReferenceTime: flight.end + Self.wakeMargin)
                ambientActive = false
            }
        } catch {
            // Cancelled: the view is going away or the layer was hidden.
        }
    }

    private static func sleep(untilReferenceTime time: TimeInterval) async throws {
        let delay = time - Date.now.timeIntervalSinceReferenceDate
        try await Task.sleep(for: .seconds(max(delay, 0)))
    }
}
