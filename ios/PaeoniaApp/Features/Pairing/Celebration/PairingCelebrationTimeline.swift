import Foundation
import QuartzCore
import SwiftUI

/// Runs the scripted pairing celebration and owns every value the view renders
/// from it.
///
/// The view calls `begin` once. The timeline then plays the intro, waits briefly
/// for the partner's name first, or settles at once (no intro, or Reduce Motion).
/// `skip` and `stop` end the intro early. Every run has an id, and each step
/// checks it after sleeping, so no step, haptic, or completion call can happen
/// after the timeline has settled.
@MainActor
@Observable
final class PairingCelebrationTimeline {
    /// Whether the celebration is still deciding, waiting for the partner's name,
    /// playing its intro, or showing the final state directly. Starting
    /// undecided avoids a one-frame flash of the settled layout before `begin`.
    enum Mode {
        case undecided
        case waitingForPartner
        case playing
        case settled
    }

    /// How large the partner's avatar is while it bursts out of the heart.
    static let heroScale: CGFloat = 1.45

    private(set) var mode: Mode = .undecided
    private(set) var phase: PairingCelebrationPhase = .heartAppearing
    private(set) var particlePlayback = PairingCelebrationParticlePlayback(started: CACurrentMediaTime())

    private(set) var heartScale: CGFloat = 0.2
    private(set) var heartOpacity: Double = 0
    private(set) var heartGlow: CGFloat = 12

    private(set) var partnerRevealed = false
    private(set) var partnerOpacity: Double = 0
    private(set) var partnerScale: CGFloat = 0.5
    private(set) var partnerLanded = false
    private(set) var partnerGlow: CGFloat = 24

    private(set) var surroundingsShown = false
    private(set) var dismissButtonShown = false

    @ObservationIgnored private let sound = PairingCelebrationSoundPlayer()
    @ObservationIgnored private let schedule: PairingCelebrationSchedule
    @ObservationIgnored private let haptics: PairingCelebrationHaptics
    @ObservationIgnored private let isPartnerPhotoLoading: @MainActor () -> Bool
    @ObservationIgnored private var onIntroComplete: (() -> Void)?
    @ObservationIgnored private var hasBegun = false
    @ObservationIgnored private var hasCompleted = false
    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var introTask: Task<Void, Never>?
    @ObservationIgnored private var hapticsTask: Task<Void, Never>?

    /// Nil uses the real schedule and haptics. Default arguments are evaluated
    /// off the main actor, so the main-actor defaults are resolved in here.
    init(
        schedule: PairingCelebrationSchedule? = nil,
        haptics: PairingCelebrationHaptics? = nil,
        isPartnerPhotoLoading: @escaping @MainActor () -> Bool = { false }
    ) {
        self.schedule = schedule ?? .standard
        self.haptics = haptics ?? .live
        self.isPartnerPhotoLoading = isPartnerPhotoLoading
    }

    var isSettled: Bool {
        phase == .settled
    }

    /// True while a tap or the VoiceOver action can still end the intro.
    var canSkip: Bool {
        mode == .waitingForPartner || (mode == .playing && phase != .settled)
    }

    /// The heart is on screen from the wait until the burst.
    var showsHeart: Bool {
        (mode == .waitingForPartner || mode == .playing) && phase <= .exploding
    }

    var showsParticles: Bool {
        mode == .playing && phase <= .exploding
    }

    // MARK: - Entry points

    /// Starts the celebration. Later calls do nothing.
    ///
    /// `onIntroComplete` fires exactly once: when the intro starts to play, when
    /// the final state is shown without an intro, or when the intro is ended early.
    func begin(
        playsIntro: Bool,
        reduceMotion: Bool,
        partnerNameKnown: Bool,
        onIntroComplete: @escaping () -> Void
    ) {
        guard !hasBegun else { return }
        hasBegun = true
        self.onIntroComplete = onIntroComplete
        if playsIntro { sound.prepare() }

        // No intro: the app launched straight into the paired space, or Reduce
        // Motion is on. Nothing waits and nothing moves. A real, fresh link still
        // gets a light success haptic.
        guard playsIntro, !reduceMotion else {
            applySettledState()
            if playsIntro {
                haptics.settledWithoutIntro()
                sound.release()
            }
            complete()
            return
        }

        if partnerNameKnown {
            play()
        } else {
            waitForPartnerName()
        }
    }

    /// The partner's name is known now. Starts the intro if it was waiting.
    func partnerNameDidArrive() {
        guard mode == .waitingForPartner else { return }
        play()
    }

    /// Jumps to the final state. Ignored when the intro is not running.
    func skip() {
        finishEarly(animated: true)
    }

    /// Ends the intro when the view goes away, so nothing keeps running.
    func stop() {
        sound.stop()
        finishEarly(animated: false)
    }

    // MARK: - Sequence

    private func finishEarly(animated: Bool) {
        guard canSkip else {
            return
        }

        cancelWork()
        if animated {
            withAnimation(PaeoniaMotion.stateChange) {
                applySettledState()
            }
        } else {
            applySettledState()
        }
        complete()
    }

    /// Shows the heart alone while the partner's name loads.
    private func waitForPartnerName() {
        mode = .waitingForPartner
        revealHeart()

        let id = beginRun()
        introTask = Task { [weak self] in
            guard let self, await pause(schedule.partnerNameWait, id) else {
                return
            }
            play()
        }
    }

    private func play() {
        // Claim the intro up front so a SwiftUI view re-creation cannot replay it.
        // The animation below runs from this timeline's own state, not the prop.
        complete()
        mode = .playing
        particlePlayback = PairingCelebrationParticlePlayback(started: CACurrentMediaTime())

        let id = beginRun()
        introTask = Task { [weak self] in
            await self?.runIntro(id)
        }
    }

    private func runIntro(_ id: Int) async {
        // A task cancelled before it first runs still starts, so check up front.
        guard isCurrent(id) else { return }
        revealHeart()
        guard await pause(schedule.heartAppear, id) else { return }

        guard await absorbParticles(id) else { return }
        await waitForPartnerPhoto(id)
        guard isCurrent(id) else { return }

        revealPartner()
        guard await pause(schedule.partnerHold, id) else { return }

        linkPartner()
        guard await pause(schedule.landingSettle, id) else { return }

        finish()
    }

    /// 1. The heart forms in the middle of the screen.
    private func revealHeart() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            heartScale = 1
            heartOpacity = 1
        }
    }

    /// 2 + 3. Particles are pulled inward while haptic pressure accumulates.
    /// Returns `false` if the sequence ended before the climax.
    private func absorbParticles(_ id: Int) async -> Bool {
        phase = .absorbing
        particlePlayback.stage = .absorbing(.init(since: CACurrentMediaTime(), duration: schedule.absorb))
        sound.absorb()
        withAnimation(.easeInOut(duration: schedule.absorb)) {
            heartScale = 1
            heartGlow = 32
        }

        hapticsTask = Task { [weak self] in
            await self?.buildHapticPressure(id)
        }
        guard await pause(max(0, schedule.absorb - 0.45), id) else { return false }
        withAnimation(.easeInOut(duration: 0.45)) {
            heartOpacity = 0.18
            heartGlow = 38
        }
        let reachedClimax = await pause(min(0.45, schedule.absorb), id)
        hapticsTask?.cancel()
        hapticsTask = nil
        return reachedClimax
    }

    /// 4. The core bursts outward and reveals the partner's avatar at the center.
    private func revealPartner() {
        phase = .exploding
        if case let .absorbing(absorption) = particlePlayback.stage {
            particlePlayback.stage = .bursting(
                absorption: absorption, since: CACurrentMediaTime(),
                releaseDuration: min(PairingCelebrationTiming.explode, schedule.partnerHold)
            )
        }
        sound.release()
        haptics.burst()
        withAnimation(.easeOut(duration: 0.22)) {
            heartScale = 1.7
            heartOpacity = 0
        }

        partnerRevealed = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.03)) {
            partnerScale = Self.heroScale
            partnerOpacity = 1
        }
    }

    /// 5. The partner glides into place and the rest of the linked state settles in.
    private func linkPartner() {
        phase = .linking
        haptics.linked()
        withAnimation(.spring(response: 0.82, dampingFraction: 0.84)) {
            partnerScale = 1
            partnerLanded = true
            partnerGlow = 7
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.86).delay(0.16)) {
            surroundingsShown = true
        }
    }

    /// 6. The intro is done and the button becomes available.
    private func finish() {
        phase = .settled
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            dismissButtonShown = true
        }
    }

    /// The final state, shown at once by Reduce Motion, a launch without an intro,
    /// a skip, or `stop`.
    private func applySettledState() {
        mode = .settled
        phase = .settled
        heartOpacity = 0
        partnerRevealed = false
        surroundingsShown = true
        dismissButtonShown = true
    }

    /// Fires `onIntroComplete` the first time and never again.
    private func complete() {
        guard !hasCompleted else {
            return
        }
        hasCompleted = true

        let callback = onIntroComplete
        onIntroComplete = nil
        callback?()
    }

    // MARK: - Timing helpers

    private func beginRun() -> Int {
        cancelWork()
        return runID
    }

    /// Cancels running tasks and invalidates their id, so a task that is already
    /// past its cancellation check still stops at its next step.
    private func cancelWork() {
        sound.stop()
        runID += 1
        introTask?.cancel()
        introTask = nil
        hapticsTask?.cancel()
        hapticsTask = nil
    }

    private func isCurrent(_ id: Int) -> Bool {
        id == runID && !Task.isCancelled
    }

    /// Sleeps for `seconds`, returning `false` if this run was cancelled or replaced.
    private func pause(_ seconds: Double, _ id: Int) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return isCurrent(id)
    }

    private func buildHapticPressure(_ id: Int) async {
        for pulse in schedule.pulses {
            guard isCurrent(id) else {
                return
            }

            haptics.buildUp(pulse.intensity)
            try? await Task.sleep(for: .seconds(pulse.gap))
        }
    }

    /// Gives the partner's photo a short moment to finish loading so the avatar
    /// does not flip from initials to a photo during the burst.
    private func waitForPartnerPhoto(_ id: Int) async {
        let deadline = CACurrentMediaTime() + schedule.partnerPhotoGrace
        while isPartnerPhotoLoading(), CACurrentMediaTime() < deadline, isCurrent(id) {
            try? await Task.sleep(for: .milliseconds(40))
        }
    }
}
