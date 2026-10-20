import Foundation
import SwiftUI

/// The haptics and sounds of the reveal, injected so tests can record them.
struct GuessMySpotRevealHaptics {
    /// A build-up pulse, a distance step or a point step.
    var tick: @MainActor (CGFloat) -> Void
    /// The real pin plants on the map.
    var landed: @MainActor () -> Void
    var spotOn: @MainActor () -> Void
    var close: @MainActor () -> Void
    var far: @MainActor () -> Void

    static let live = Self(
        tick: { intensity in
            PaeoniaHaptics.streakTick(intensity: intensity)
            GameSound.tick.play(volume: intensity + 0.1)
        },
        landed: {
            PaeoniaHaptics.answerRevealed()
            GameSound.chime.play()
        },
        spotOn: {
            PaeoniaHaptics.streakCelebrated()
            GameSound.win.play()
        },
        close: {
            PaeoniaHaptics.streakContinued()
            GameSound.bonus.play()
        },
        far: {
            PaeoniaHaptics.partnerDrawingReceived()
            GameSound.soft.play()
        }
    )
}

/// Runs the reveal of a round and owns every value the view draws from it. The
/// view calls `begin` once. The beats then play on a schedule, or the settled
/// state shows at once (Reduce Motion or a tap).
///
/// Every run has an id and each step checks it after sleeping, so no step or
/// haptic can happen after the timeline settled or stopped.
@MainActor
@Observable
final class GuessMySpotRevealTimeline {
    typealias Plan = GuessMySpotRevealPlan
    typealias Schedule = GuessMySpotRevealSchedule

    /// Where the camera is in the reveal. The view moves the map's camera when it changes.
    enum Camera: Equatable {
        /// On the guess.
        case guess
        /// Both spots in view.
        case overview
        /// On the real spot.
        case landed
    }

    // MARK: State the view draws

    /// The photo has slid away and the map fills the screen.
    private(set) var photoAway = false
    /// The guess pin's head scale during a build-up pulse, 1 at rest.
    private(set) var pulseScale: CGFloat = 1
    /// Both heads' scale for the spot on spring, 1 at rest.
    private(set) var verdictScale: CGFloat = 1
    /// The distance capsule's scale when the verdict lands, 1 at rest.
    private(set) var capsuleScale: CGFloat = 1
    /// How strongly both heads glow gold once the verdict is in: 1 spot on, 0.8 close, 0 far.
    private(set) var glow: CGFloat = 0
    /// The gold ring that widens from the real pin at the verdict, 0 to 1. Nil when there is none.
    private(set) var ring: CGFloat?
    private(set) var camera: Camera = .guess
    /// How much of the line is drawn, 0 to 1.
    private(set) var lineProgress: Double = 0
    /// The real pin is on the map.
    private(set) var dropped = false
    /// How far above its spot the real pin still floats while it drops, in points.
    private(set) var dropLift: CGFloat = 0
    /// The real pin has hit the map, and the screen holds still before the flight down.
    private(set) var planted = false
    /// How far the distance has counted, in steps of `schedule.distanceSteps`.
    private(set) var distanceStep = 0
    private(set) var verdict: GuessMySpotVerdict?
    /// When the petal bloom started. Nil before it and after it.
    private(set) var bloomStart: Date?
    private(set) var cardShown = false
    /// How far the points have counted, in steps of `schedule.pointSteps`.
    private(set) var pointStep = 0
    private(set) var actionsShown = false
    private(set) var isSettled = false

    @ObservationIgnored let schedule: Schedule
    @ObservationIgnored private let haptics: GuessMySpotRevealHaptics
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private(set) var plan: Plan?
    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Runs before each camera move, until that move's map images are ready.
    @ObservationIgnored private var prepare: @MainActor (Camera) async -> Void = { _ in }

    init(
        schedule: Schedule = .standard,
        haptics: GuessMySpotRevealHaptics? = nil,
        now: @escaping () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.schedule = schedule
        self.haptics = haptics ?? .live
        self.now = now
        self.sleep = sleep
    }

    /// The first frame of a held reveal: the guess pin alone on the map.
    func hold() {
        guard plan == nil else { return }
        withAnimation(PaeoniaMotion.meaningfulMoment) {
            photoAway = true
        }
    }

    /// Starts the reveal. Later calls do nothing. Each camera move waits for
    /// `prepare` to return, and every beat after it waits as long.
    func begin(
        _ plan: Plan,
        reduceMotion: Bool,
        prepare: @escaping @MainActor (Camera) async -> Void = { _ in }
    ) {
        guard self.plan == nil else { return }
        self.plan = plan
        self.prepare = prepare
        if reduceMotion {
            applySettledState(plan, camera: .overview)
            playVerdictHaptic(plan.verdict)
            return
        }
        start(GuessMySpotRevealScript.steps(for: plan, schedule: schedule))
    }

    /// Jumps to the settled state without repeating haptics.
    func skip() {
        guard canSkip, let plan else { return }
        cancelRun()
        withAnimation(PaeoniaMotion.stateChange) {
            applySettledState(plan, camera: .landed)
        }
    }

    /// Ends the run when the view goes away.
    func stop() {
        guard hasBegun, !isSettled, let plan else { return }
        cancelRun()
        applySettledState(plan, camera: .landed)
    }

    // MARK: Script

    private func start(_ steps: [GuessMySpotRevealStep]) {
        runID += 1
        let id = runID
        task = Task { [weak self] in
            await self?.run(steps, id: id)
        }
    }

    private func run(_ steps: [GuessMySpotRevealStep], id: Int) async {
        var elapsed: TimeInterval = 0
        for step in steps {
            let wait = step.at - elapsed
            if wait > 0 {
                try? await sleep(.seconds(wait))
                elapsed = step.at
            }
            guard id == runID, !Task.isCancelled else { return }
            if let stage = Self.camera(after: step.event) {
                await prepare(stage)
                guard id == runID, !Task.isCancelled else { return }
            }
            apply(step.event)
        }
        guard id == runID, !Task.isCancelled else { return }
        isSettled = true
    }

    private func apply(_ event: GuessMySpotRevealEvent) {
        switch event {
        case .start, .pulse, .zoomOut, .line, .drop, .land, .distance:
            applyBuildUp(event)
        case .verdict, .bloomEnd, .card, .points, .actions:
            applyResult(event)
        }
    }

    /// The beats before the verdict: the photo away, the pulses, the flight, the
    /// line, the drop and the distance.
    private func applyBuildUp(_ event: GuessMySpotRevealEvent) {
        switch event {
        case .start:
            withAnimation(PaeoniaMotion.meaningfulMoment) {
                photoAway = true
            }
        case let .pulse(intensity):
            haptics.tick(intensity)
            // Up to 1.16 and back, as a sine over 0.3 s.
            tween(0.3) { [weak self] fraction in
                self?.pulseScale = 1 + 0.16 * sin(fraction * .pi)
            }
        case .zoomOut:
            camera = .overview
        case .line:
            // Eases out: the line leaves the guess at once and slows into the spot.
            tween(schedule.lineDuration) { [weak self] fraction in
                self?.lineProgress = 1 - pow(1 - fraction, 2)
            }
        case .drop:
            drop()
        case .land:
            camera = .landed
        case let .distance(step):
            haptics.tick(GuessMySpotRevealScript.distanceIntensity)
            withAnimation(PaeoniaMotion.buttonPress) {
                distanceStep = step
            }
        default:
            break
        }
    }

    /// The verdict and what follows it: the bloom, the card, the points and the button.
    private func applyResult(_ event: GuessMySpotRevealEvent) {
        switch event {
        case let .verdict(verdict):
            land(verdict)
        case .bloomEnd:
            bloomStart = nil
        case .card:
            withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                cardShown = true
            }
        case let .points(step):
            haptics.tick(GuessMySpotRevealScript.pointIntensity)
            withAnimation(PaeoniaMotion.buttonPress) {
                pointStep = step
            }
        case .actions:
            withAnimation(PaeoniaMotion.cardReveal) {
                actionsShown = true
            }
        default:
            break
        }
    }

    private func playVerdictHaptic(_ verdict: GuessMySpotVerdict) {
        switch verdict {
        case .spotOn: haptics.spotOn()
        case .soClose, .close: haptics.close()
        case .far: haptics.far()
        }
    }

    private func applySettledState(_ plan: Plan, camera: Camera) {
        photoAway = true
        self.camera = camera
        pulseScale = 1
        verdictScale = 1
        capsuleScale = 1
        glow = Self.glow(for: plan.verdict)
        ring = nil
        lineProgress = 1
        dropped = true
        dropLift = 0
        planted = true
        distanceStep = schedule.distanceSteps
        verdict = plan.verdict
        bloomStart = nil
        cardShown = true
        pointStep = schedule.pointSteps
        actionsShown = true
        isSettled = true
    }

    /// The real pin falls onto the end of the line, and the chime plays as it hits.
    private func drop() {
        dropped = true
        dropLift = Self.dropHeight
        tween(schedule.fallDuration) { [weak self] fraction in
            guard let self else { return }
            dropLift = Self.dropHeight * (1 - fraction * fraction)
            // The last step is the only one at 1.
            if fraction >= 1 {
                planted = true
                haptics.landed()
            }
        }
    }

    /// The verdict: its haptic, the glow on both heads, the capsule's pulse, the
    /// spot on spring and bloom, and the gold ring from the real pin.
    private func land(_ verdict: GuessMySpotVerdict) {
        playVerdictHaptic(verdict)
        if verdict == .spotOn {
            bloomStart = now()
        }
        withAnimation(PaeoniaMotion.cardReveal) {
            self.verdict = verdict
        }
        let target = Self.glow(for: verdict)
        let springs = verdict == .spotOn
        tween(0.3) { [weak self] fraction in
            self?.glow = target * fraction
            self?.capsuleScale = 1 + 0.1 * sin(fraction * .pi)
            if springs { self?.verdictScale = 1 + 0.25 * sin(fraction * .pi) }
        }
        if verdict != .far {
            tween(0.4) { [weak self] fraction in
                self?.ring = fraction < 1 ? fraction : nil
            }
        }
    }

    /// How high the real pin starts its drop, in points.
    static let dropHeight: CGFloat = 70

    /// Moves a value over `duration`, about 60 times a second, in this run only. A
    /// map's pins and lines don't take SwiftUI's animations, so the timeline steps
    /// them. Each step reads the clock, so a late frame never makes the move run long.
    private func tween(_ duration: TimeInterval, _ update: @escaping @MainActor (Double) -> Void) {
        let id = runID
        let start = ContinuousClock.now
        Task { [weak self, sleep] in
            while true {
                try? await sleep(.milliseconds(16))
                guard let self, id == runID, !Task.isCancelled else { return }
                let fraction = min(1, (ContinuousClock.now - start) / .seconds(duration))
                update(fraction)
                if fraction >= 1 { return }
            }
        }
    }

    private func cancelRun() {
        runID += 1
        task?.cancel()
        task = nil
    }
}

extension GuessMySpotRevealTimeline {
    var hasBegun: Bool { plan != nil }

    /// A tap can end the reveal early once the verdict is in.
    var canSkip: Bool { hasBegun && verdict != nil && !isSettled }

    /// The distance as the capsule shows it right now.
    var countedDistance: Int {
        guard let plan else { return 0 }
        return GuessMySpotRevealScript.counted(plan.distanceMeters, step: distanceStep, of: schedule.distanceSteps)
    }

    /// How many of the round's points have counted up.
    var countedPoints: Int {
        guard let plan else { return 0 }
        return GuessMySpotRevealScript.counted(plan.points, step: pointStep, of: schedule.pointSteps)
    }

    static func glow(for verdict: GuessMySpotVerdict) -> CGFloat {
        switch verdict {
        case .spotOn: 1
        case .soClose, .close: 0.8
        case .far: 0
        }
    }

    /// Where `event` moves the camera, if it does.
    private static func camera(after event: GuessMySpotRevealEvent) -> Camera? {
        switch event {
        case .zoomOut: .overview
        case .land: .landed
        default: nil
        }
    }
}
