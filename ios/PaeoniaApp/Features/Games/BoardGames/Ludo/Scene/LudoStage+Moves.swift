import RealityKit
import simd
import UIKit

/// Showing the board: the moves that animate and the changes that snap.
extension LudoStage {
    /// Brings the scene to the new board. Returns the move when it was one the
    /// stage had not seen and could follow.
    func syncBoard(_ new: Input) -> PresentedMove? {
        guard let move = new.lastMove else {
            presentedNumber = 0
            if new.board != shownBoard || !hasShownBoard { snap(new.board) }
            return nil
        }
        guard let presented = presentedNumber else {
            presentedNumber = move.number
            snap(new.board)
            return nil
        }
        if move.number > presented {
            presentedNumber = move.number
            if let result = shownBoard.resolve(move.move), result.board == new.board {
                let old = shownBoard
                shownBoard = new.board
                play(result.transition, from: old, to: new.board, isMine: move.isMine)
                return PresentedMove(transition: result.transition, isMine: move.isMine)
            }
            if new.board != shownBoard { snap(new.board) }
            return nil
        }
        presentedNumber = move.number
        if new.board != shownBoard { snap(new.board) }
        return nil
    }

    /// Shows a board at once, with no animation.
    func snap(_ board: LudoBoard) {
        finishAllClips()
        shownBoard = board
        hasShownBoard = true
        let placements = LudoBoardGeometry.placements(board: board, viewer: viewer)
        for (pawn, placement) in zip(pawns, placements) {
            pawn.setRest(position: LudoWorld.position(of: placement), scale: Float(placement.scale))
            pawn.jumpToRest()
        }
    }

    // MARK: A move

    private func play(_ transition: LudoTransition, from old: LudoBoard, to new: LudoBoard, isMine: Bool) {
        finishAllClips()
        let placements = LudoBoardGeometry.placements(board: new, viewer: viewer)
        let starts = pawns.map { ($0.rest, $0.restScale) }
        for (pawn, placement) in zip(pawns, placements) {
            pawn.setRest(position: LudoWorld.position(of: placement), scale: Float(placement.scale))
        }
        if !isMine { tumblePartnerDie(to: transition.die) }
        guard let index = transition.pawn, pawns.indices.contains(index) else { return }

        // The partner's pawn waits for the die to tumble on their tray.
        let lead = isMine ? 0 : (reduceMotion ? 0.2 : LudoSceneStyle.tumbleDuration + LudoSceneStyle.partnerPause)
        let begin = clock + lead
        let moverDuration: Double
        if reduceMotion {
            moverDuration = LudoSceneStyle.fadeDuration
            fadeMove(pawns[index], from: starts[index], start: begin, transition: transition)
        } else {
            moverDuration = hopMove(
                pawns[index],
                from: starts[index],
                start: begin,
                transition: transition,
                board: new
            )
        }
        let landing = begin + moverDuration
        for sent in transition.sentHome where pawns.indices.contains(sent) {
            sendHome(pawns[sent], from: starts[sent], start: landing, movedByMe: isMine)
        }
    }

    /// The pawn hops square by square, 0.16 seconds each, with a tap on every landing.
    private func hopMove(
        _ pawn: LudoPawnNode,
        from start: (SIMD3<Float>, Float),
        start begin: Double,
        transition: LudoTransition,
        board: LudoBoard
    ) -> Double {
        let hop = LudoSceneStyle.hopDuration
        var points = [start.0]
        for (step, square) in transition.path.enumerated() {
            if step == transition.path.count - 1 {
                points.append(pawn.rest)
            } else {
                let point = LudoBoardGeometry.point(of: square, homeLane: pawn.index % 2, viewer: viewer)
                points.append(LudoWorld.position(point, height: LudoWorld.standingHeight(on: square)))
            }
        }
        let hops = max(points.count - 1, 1)
        let duration = Double(hops) * hop
        var events: [LudoClip.Event] = (1...hops).map { step in
            let isLast = step == hops
            return LudoClip.Event(time: Double(step) * hop) {
                PaeoniaHaptics.streakTick(intensity: isLast ? 0.55 : 0.35)
            }
        }
        let reachesHome = transition.path.last == .home(pawn.player)
        if reachesHome {
            let player = pawn.player
            events.append(LudoClip.Event(time: duration) { [weak self] in
                PaeoniaHaptics.streakContinued()
                self?.pulseHome(of: player)
            })
        }
        let startScale = start.1
        let endScale = pawn.restScale
        add(LudoClip(owner: .pawn(pawn.index), start: begin, duration: duration, events: events) { time in
            let position = LudoMotion.hops(through: points, elapsed: time, hopDuration: hop, arc: LudoSceneStyle.hopArc)
            let scale = startScale + (endScale - startScale) * Float(LudoMotion.smooth(time / duration))
            pawn.apply(position: position, scale: scale)
        })
        return duration
    }

    /// Reduce Motion: the pawn fades out where it was and fades in on its new square.
    private func fadeMove(
        _ pawn: LudoPawnNode,
        from start: (SIMD3<Float>, Float),
        start begin: Double,
        transition: LudoTransition
    ) {
        let duration = LudoSceneStyle.fadeDuration
        let half = duration / 2
        let rest = pawn.rest
        let restScale = pawn.restScale
        let reachesHome = transition.path.last == .home(pawn.player)
        let player = pawn.player
        let events = [LudoClip.Event(time: duration) { [weak self] in
            PaeoniaHaptics.streakTick(intensity: 0.5)
            if reachesHome { self?.pulseHome(of: player) }
        }]
        let clip = LudoClip(owner: .pawn(pawn.index), start: begin, duration: duration, events: events) { time in
            if time < half {
                pawn.apply(position: start.0, scale: start.1)
                pawn.fade = Float(1 - time / half)
            } else {
                pawn.apply(position: rest, scale: restScale)
                pawn.fade = Float((time - half) / half)
            }
        }
        clip.onFinish = { pawn.fade = 1 }
        add(clip)
    }

    /// A partner pawn that was sent home pops up, arcs back to its base and settles.
    private func sendHome(
        _ pawn: LudoPawnNode,
        from start: (SIMD3<Float>, Float),
        start begin: Double,
        movedByMe: Bool
    ) {
        let duration = reduceMotion ? LudoSceneStyle.fadeDuration : LudoSceneStyle.sendHomeDuration
        let rest = pawn.rest
        let restScale = pawn.restScale
        let tap = LudoClip.Event(time: 0) {
            if movedByMe {
                PaeoniaHaptics.streakTick(intensity: 0.8)
            } else {
                PaeoniaHaptics.partnerDrawingReceived()
            }
        }
        let clip: LudoClip
        if reduceMotion {
            let half = duration / 2
            clip = LudoClip(owner: .pawn(pawn.index), start: begin, duration: duration, events: [tap]) { time in
                if time < half {
                    pawn.apply(position: start.0, scale: start.1)
                    pawn.fade = Float(1 - time / half)
                } else {
                    pawn.apply(position: rest, scale: restScale)
                    pawn.fade = Float((time - half) / half)
                }
            }
            clip.onFinish = { pawn.fade = 1 }
        } else {
            clip = LudoClip(owner: .pawn(pawn.index), start: begin, duration: duration, events: [tap]) { time in
                let position = LudoMotion.sendHome(from: start.0, to: rest, elapsed: time, duration: duration)
                let scale = start.1 + (restScale - start.1) * Float(LudoMotion.smooth(time / duration))
                pawn.apply(position: position, scale: scale)
            }
        }
        add(clip)
    }

    /// The pad where a pawn came home pulses in the player's color.
    func pulseHome(of player: BoardPlayer) {
        let slot = player.rawValue - 1
        let duration = LudoSceneStyle.homePulseDuration
        let clip = LudoClip(owner: .glow(slot), start: clock, duration: duration) { [weak self] time in
            self?.glowPulses[slot] = Float(sin(Double.pi * time / duration))
        }
        clip.onFinish = { [weak self] in self?.glowPulses[slot] = 0 }
        add(clip)
    }
}
