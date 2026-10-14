import RealityKit
import simd
import UIKit

/// The die: which base yard it rests in, the tumble and the hop between yards.
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

        if case let .rolling(value, _, token) = state {
            guard token != lastTumbleToken else { return }
            lastTumbleToken = token
            if !isNear, afterPartnerMove { return }
            partnerLiveRoll = isNear ? nil : (value, clock + LudoSceneStyle.tumbleDuration)
            tumble(die, to: value, tray: tray, isNear: isNear)
            return
        }
        // A tumble finishes first. Then the die follows the newest state.
        if clips.contains(where: { $0.owner == .die && $0.isTumble }) { return }

        switch state {
        case let .showing(value, _):
            let orientation = LudoDieFaces.orientation(showing: value)
            place(die, position: tray, orientation: orientation, isNear: isNear, face: value)
        case .idle, .ready:
            place(die, position: tray, orientation: die.restOrientation, isNear: isNear, face: nil)
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

    /// The partner's move arrived: the die tumbles on their tray and lands with
    /// the number they rolled. It stays showing that face.
    func tumblePartnerDie(to value: Int) {
        guard let die = dieNode else { return }
        tumble(die, to: value, tray: LudoWorld.dieRestPosition(isNear: false), isNear: false)
    }

    /// The die tumbles on `tray` and lands with `value` up.
    private func tumble(_ die: LudoDieNode, to value: Int, tray: SIMD3<Float>, isNear: Bool) {
        finishDieClip()
        let orientation = LudoDieFaces.orientation(showing: value)
        guard diePlaced, !reduceMotion else {
            snapDie(die, position: tray, orientation: orientation, isNear: isNear, face: value)
            return
        }
        let startPosition = die.currentPosition
        let startOrientation = die.currentOrientation
        let duration = LudoSceneStyle.tumbleDuration
        die.setRest(position: tray, orientation: orientation, isNear: isNear, face: value)
        let landings = LudoMotion.tumbleLandings()
        let events: [LudoClip.Event] = landings.enumerated().map { number, share in
            let isLast = number == landings.count - 1
            return LudoClip.Event(time: share * duration) {
                if isLast {
                    PaeoniaHaptics.streakTick(intensity: 0.55)
                } else {
                    PaeoniaHaptics.selection()
                }
            }
        }
        let clip = LudoClip(owner: .die, start: clock, duration: duration, isTumble: true, events: events) { time in
            let progress = time / duration
            die.apply(
                position: LudoMotion.tumblePosition(from: startPosition, to: tray, progress: progress),
                orientation: LudoMotion.tumbleOrientation(from: startOrientation, to: orientation, progress: progress),
                scale: 1
            )
        }
        clip.onFinish = { [weak self] in
            guard let self, let state = input?.die else { return }
            syncDie(state)
        }
        add(clip)
    }

    /// Puts the die where the state says. It hops there if it is somewhere else now.
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
        die.setRest(position: position, orientation: orientation, isNear: isNear, face: face)
        add(LudoClip(owner: .die, start: clock, duration: duration) { time in
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

    private func finishDieClip() {
        guard let clip = clips.first(where: { $0.owner == .die }) else { return }
        clip.finishNow()
        clips.removeAll { $0 === clip }
    }
}
