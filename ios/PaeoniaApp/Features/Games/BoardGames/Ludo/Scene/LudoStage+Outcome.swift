import RealityKit
import Foundation

/// The result: the winner's home glows and the other pawns dim to 40%. The
/// petal bloom is drawn by the board view above the scene.
extension LudoStage {
    /// Starts the result when the screen asks for it. Returns the seconds until it
    /// starts, which waits for the last move to finish. Nil when nothing starts now.
    func syncOutcome(_ new: Input) -> Double? {
        guard new.showsOutcome, let winner = new.board.outcome?.winner else {
            // The winning pawn's glow waits here for the result to start.
            if new.board.outcome?.winner != nil, outcomeWinner == nil { return nil }
            clearOutcome()
            return nil
        }
        guard outcomeWinner != winner else { return nil }
        outcomeWinner = winner
        if reduceMotion {
            showOutcome(winner: winner, immediately: true)
            PaeoniaHaptics.answerRevealed()
            return 0
        }
        // The pawns finish first. The die may still hop to the next yard.
        let delay = pawnTimeLeft
        outcomeSchedule = OutcomeSchedule(start: clock + delay, winner: winner)
        return delay
    }

    /// Runs the beats of the result as the clock reaches them.
    func updateOutcomeSchedule() {
        guard var schedule = outcomeSchedule else { return }
        if !schedule.hasStarted, clock >= schedule.start {
            schedule.hasStarted = true
            showOutcome(winner: schedule.winner, immediately: false)
        }
        if !schedule.hasTapped, clock >= schedule.start + LudoSceneStyle.bloomDelay {
            schedule.hasTapped = true
            PaeoniaHaptics.answerRevealed()
        }
        outcomeSchedule = schedule.hasTapped ? nil : schedule
    }

    private func showOutcome(winner: BoardPlayer, immediately: Bool) {
        for pawn in pawns {
            pawn.dimTarget = pawn.player == winner ? 1 : LudoSceneStyle.dimmedOpacity
            if immediately { pawn.snapDim() }
        }
        let slot = winner.rawValue - 1
        glowTargets[slot] = 1
        if immediately { glowLevels[slot] = 1 }
    }

    private func clearOutcome() {
        guard outcomeWinner != nil || outcomeSchedule != nil || glowTargets != [0, 0] else { return }
        outcomeWinner = nil
        outcomeSchedule = nil
        for pawn in pawns {
            pawn.dimTarget = 1
            pawn.snapDim()
        }
        glowTargets = [0, 0]
        glowLevels = [0, 0]
    }

    /// Eases the glow plates under the home pads and applies them to the scene.
    func updateGlows(deltaTime: Double) {
        guard homeGlows.count == 2 else { return }
        let rate = Float(1 - exp(-deltaTime * 3 / LudoSceneStyle.outcomeGlowDuration))
        let breathing = Float(0.78 + 0.22 * sin(clock * 2.4))
        for slot in 0..<2 {
            glowLevels[slot] += (glowTargets[slot] - glowLevels[slot]) * rate
            let value = max(glowLevels[slot] * breathing, glowPulses[slot])
            guard abs(value - appliedGlows[slot]) > 0.004 else { continue }
            appliedGlows[slot] = value
            let glow = homeGlows[slot]
            glow.isEnabled = value > 0.01
            glow.components.set(OpacityComponent(opacity: min(max(value, 0), 1)))
        }
    }
}
