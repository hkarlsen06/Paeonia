import RealityKit
import simd
import UIKit

/// The die: which base yard it rests in, the throw and the hop between yards.
extension LudoStage {
    /// Brings the die to the state the screen asks for.
    ///
    /// My rolls come from the screen as `.rolling(side: me)`. My partner's come
    /// as `.rolling(side: partner)` when their roll arrives live, and the stage
    /// remembers it so their move does not tumble the die again. Without a live
    /// roll the stage tumbles the die by itself when the partner's move arrives
    /// (see `tumblePartnerDie`).
    func syncDie(_ state: LudoDieState, afterPartnerMove: Bool = false) {
        guard let die = dieNode else { return }
        let isNear = state.side(me: viewer) == viewer
        let tray = LudoWorld.dieRestPosition(isNear: isNear)

        if case let .rolling(value, _, token, toss) = state {
            guard token != lastTumbleToken else { return }
            lastTumbleToken = token
            if !isNear, afterPartnerMove { return }
            let duration = tumble(die, to: value, toss: toss, isNear: isNear)
            partnerLiveRoll = isNear ? nil : (value, clock + duration)
            return
        }
        // A tumble finishes first. Then the die follows the newest state.
        if clips.contains(where: { $0.owner == .die && $0.isTumble }) { return }

        settle(die, in: state, tray: tray, isNear: isNear)
    }

    /// Puts a die that is not thrown where `state` says. It stays where it landed
    /// while it stays in that yard.
    private func settle(_ die: LudoDieNode, in state: LudoDieState, tray: SIMD3<Float>, isNear: Bool) {
        let staysPut = die.restsOnNearTray == isNear
        switch state {
        case let .showing(value, _) where staysPut && die.shownFace == value:
            place(die, position: die.restPosition, orientation: die.restOrientation, isNear: isNear, face: value)
        case let .showing(value, _):
            let orientation = LudoDieFaces.orientation(showing: value)
            place(die, position: tray, orientation: orientation, isNear: isNear, face: value)
        case .idle, .ready:
            let position = staysPut ? die.restPosition : tray
            place(die, position: position, orientation: die.restOrientation, isNear: isNear, face: nil)
        case .rolling:
            break
        }
    }

    /// Takes the partner's live roll when it matches the move that arrived, and
    /// returns how much of its tumble is left. Nil means the die has not tumbled yet.
    func takePartnerLiveRoll(matching value: Int) -> Double? {
        defer { partnerLiveRoll = nil }
        guard let roll = partnerLiveRoll, roll.die == value else { return nil }
        return max(0, roll.endsAt - clock)
    }

    /// The partner's move arrived without their live roll: the die is thrown on
    /// their tray and lands with the number they rolled. Returns how long it takes.
    func tumblePartnerDie(to value: Int) -> Double {
        guard let die = dieNode else { return 0 }
        let toss = LudoToss.tap(seed: UInt64(truncatingIfNeeded: presentedNumber ?? 0))
        return tumble(die, to: value, toss: toss, isNear: false)
    }

    /// The die flies along the simulated throw and lands with `value` up, wherever
    /// in the yard the throw takes it. Returns how long that takes.
    private func tumble(_ die: LudoDieNode, to value: Int, toss: LudoToss, isNear: Bool) -> Double {
        // A die the finger let go has flown on since. Its flight picks up from there.
        let thrownAgo = isNear ? releasedAt.map { clock - $0 } : nil
        heldDie = nil
        releasedAt = nil
        releasedToss = nil
        finishDieClip()
        guard diePlaced, !reduceMotion else {
            let tray = LudoWorld.dieRestPosition(isNear: isNear)
            let orientation = LudoDieFaces.orientation(showing: value)
            snapDie(die, position: tray, orientation: orientation, isNear: isNear, face: value)
            return 0
        }
        let roller = isNear ? viewer : viewer.other
        let tray = LudoDieTray.near(waitingSlots: waitingSlots(of: roller))
        let flight = LudoDiePhysics.flight(for: toss, showing: value, in: tray)
        let end = Self.worldPose(flight.pose(at: flight.duration), isNear: isNear)
        die.setRest(position: end.position, orientation: end.orientation, isNear: isNear, face: value)
        let start = (die.currentPosition, die.currentOrientation)
        let clip = flightClip(die, flight: flight, from: start, thrownAgo: thrownAgo, isNear: isNear)
        add(clip)
        return clip.end - clock
    }

    /// The clip of a throw. A die the finger let go `thrownAgo` seconds ago starts
    /// that far into the flight and eases onto it from where it flew. Any other die
    /// rises into the throw over `tossPickUpTime`, then follows the flight.
    private func flightClip(
        _ die: LudoDieNode,
        flight: LudoDieFlight,
        from start: (position: SIMD3<Float>, orientation: simd_quatf),
        thrownAgo: Double?,
        isNear: Bool
    ) -> LudoClip {
        let lead = thrownAgo == nil ? LudoSceneStyle.tossPickUpTime : 0
        let skipped = min(thrownAgo ?? 0, flight.duration)
        let first = Self.worldPose(flight.pose(at: 0), isNear: isNear)
        let joined = Self.worldPose(flight.pose(at: skipped), isNear: isNear)
        let offset = start.position - joined.position
        let turn = simd_normalize(start.orientation * joined.orientation.inverse)
        let still = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        let duration = lead + flight.duration
        let events = flightEvents(flight, skipped: skipped, lead: lead, isNear: isNear)
        let clip = LudoClip(
            owner: .die,
            start: clock - skipped,
            duration: duration,
            isTumble: true,
            events: events
        ) { time in
            if time < lead {
                let amount = Float(LudoMotion.smooth(time / lead))
                die.apply(
                    position: simd_mix(start.position, first.position, SIMD3(repeating: amount)),
                    orientation: simd_slerp(start.orientation, first.orientation, amount),
                    scale: 1
                )
            } else {
                var pose = Self.worldPose(flight.pose(at: time - lead), isNear: isNear)
                let catchUp = (time - skipped) / LudoSceneStyle.tossCatchUpTime
                if lead == 0, catchUp < 1 {
                    let amount = Float(LudoMotion.smooth(catchUp))
                    pose.position += offset * (1 - amount)
                    pose.orientation = simd_normalize(simd_slerp(turn, still, amount) * pose.orientation)
                }
                die.apply(position: pose.position, orientation: pose.orientation, scale: 1)
            }
        }
        clip.onFinish = { [weak self] in
            guard let self, let state = input?.die else { return }
            syncDie(state)
        }
        return clip
    }

    /// The knocks along a flight, then the settle. Each knock is a little quieter
    /// than the one before, as the die loses speed. My die tells the screen it landed.
    private func flightEvents(
        _ flight: LudoDieFlight,
        skipped: Double,
        lead: Double,
        isNear: Bool
    ) -> [LudoClip.Event] {
        var events = flight.knocks.filter { $0 >= skipped }.enumerated().map { index, time in
            LudoClip.Event(time: lead + time) {
                PaeoniaHaptics.selection()
                GameSound.ludoDieKnock.play(volume: max(0.35, 1 - 0.22 * Double(index)))
            }
        }
        events.append(LudoClip.Event(time: lead + flight.duration) { [weak self] in
            PaeoniaHaptics.streakTick(intensity: 0.55)
            GameSound.ludoDieSettle.play(volume: 0.7)
            if isNear { self?.onDieLanded?() }
        })
        return events
    }

    /// A die put down without a throw drops back to where it rests.
    func returnDieToRest() {
        guard let die = dieNode else { return }
        let rest = die.restPosition
        let orientation = die.restOrientation
        guard !reduceMotion else {
            die.apply(position: rest, orientation: orientation, scale: 1)
            return
        }
        let start = die.currentPosition
        let turn = die.currentOrientation
        let duration = LudoSceneStyle.trayHopDuration
        add(LudoClip(owner: .die, start: clock, duration: duration) { time in
            let amount = LudoMotion.smooth(time / duration)
            die.apply(
                position: simd_mix(start, rest, SIMD3(repeating: Float(amount))),
                orientation: simd_slerp(turn, orientation, Float(amount)),
                scale: 1
            )
        })
    }

    /// Puts the die where the state says. It hops there if it is somewhere else now.
    /// A die that changes yards waits for the pawns to land, so the eye follows one
    /// thing at a time.
    private func place(
        _ die: LudoDieNode,
        position: SIMD3<Float>,
        orientation: simd_quatf,
        isNear: Bool,
        face: Int?
    ) {
        let samePlace = simd_distance(die.restPosition, position) < 0.001
        let sameTurn = abs(simd_dot(die.restOrientation, orientation)) > 0.9999
        guard !(samePlace && sameTurn) else {
            die.setRest(position: position, orientation: orientation, isNear: isNear, face: face)
            diePlaced = true
            return
        }
        guard diePlaced, !reduceMotion else {
            snapDie(die, position: position, orientation: orientation, isNear: isNear, face: face)
            return
        }
        finishDieClip()
        let startPosition = die.currentPosition
        let startOrientation = die.currentOrientation
        let duration = LudoSceneStyle.trayHopDuration
        let wait = die.restsOnNearTray == isNear ? 0 : pawnTimeLeft
        die.setRest(position: position, orientation: orientation, isNear: isNear, face: face)
        add(LudoClip(owner: .die, start: clock + wait, duration: duration) { time in
            let progress = LudoMotion.clamped(time / duration)
            die.apply(
                position: LudoMotion.trayHop(from: startPosition, to: position, progress: progress),
                orientation: simd_slerp(startOrientation, orientation, Float(LudoMotion.smooth(progress))),
                scale: 1
            )
        })
    }

    private func snapDie(
        _ die: LudoDieNode,
        position: SIMD3<Float>,
        orientation: simd_quatf,
        isNear: Bool,
        face: Int?
    ) {
        finishDieClip()
        die.setRest(position: position, orientation: orientation, isNear: isNear, face: face)
        die.apply(position: position, orientation: orientation, scale: 1)
        diePlaced = true
    }

    func finishDieClip() {
        guard let clip = clips.first(where: { $0.owner == .die }) else { return }
        clip.finishNow()
        clips.removeAll { $0 === clip }
    }
}
