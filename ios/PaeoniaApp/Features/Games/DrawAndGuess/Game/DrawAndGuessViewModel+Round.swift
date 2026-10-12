import PencilKit
import SwiftUI

// What changes when the round changes: the guesser's tiles, the drawer's canvas,
// and the numbers on the reveal.
extension DrawAndGuessViewModel {
    /// Sets up the tiles for a guesser and the canvas for a drawer when a new
    /// round starts.
    func syncRoundState() {
        guard let userID = currentUserID else { return }

        if round?.id != replayRoundID {
            resetReplay()
            replayRoundID = round?.id
        }

        if let round, !round.isDrawer(userID), let language = settings?.language {
            if tilesRoundID != round.id || tilesLanguage != language {
                wrongGuessTask?.cancel()
                // The seed is the round id, so both phones build the same tiles.
                tiles = DrawAndGuessTiles.make(
                    answer: round.word,
                    language: language,
                    seed: round.id.uuidString.lowercased()
                )
                slots = DrawAndGuessSlots(answer: round.word)
                tilesRoundID = round.id
                tilesLanguage = language
                isShowingWrongGuess = false
            }
        } else if tilesRoundID != nil {
            tiles = []
            slots = DrawAndGuessSlots(answer: "")
            tilesRoundID = nil
            tilesLanguage = nil
        }

        if let round, round.isDrawer(userID), !round.isFinished, boardRoundID != round.id {
            boardRoundID = round.id
            board.reset()
            if let draft = startingDrawing(for: round, userID: userID) {
                // The draft is at the canonical size. The board scales it at layout.
                board.replace(with: draft)
            }
            live?.drawingReplacedFromCode(board.drawing)
        }
    }

    /// What the canvas starts with: this round's draft, or the drawing made for a
    /// word the server refused. The refused drawing becomes this round's draft
    /// first, so closing the app now does not lose it.
    private func startingDrawing(for round: DrawAndGuessRoundView, userID: UUID) -> PKDrawing? {
        let store = dependencies.drawingStore
        if let data = store.draft(ownerUserID: userID, roundID: round.id), let draft = try? PKDrawing(data: data) {
            return draft
        }
        guard let data = store.rescuedDrawing(ownerUserID: userID), let rescued = try? PKDrawing(data: data) else {
            return nil
        }
        store.saveDraft(data, ownerUserID: userID, roundID: round.id)
        store.removeRescuedDrawing(ownerUserID: userID)
        return rescued
    }

    /// Forgets the drawing of the round that ended, so the next one starts clean.
    func resetReplay() {
        downloadedDrawing = nil
        loadedAssetID = nil
        cancelDrawingLoad()
        drawingLoadFailed = false
        replayTimeline = nil
        replayClock = nil
        isReplayReady = false
        isFastForwarding = false
        guessSource = .replay
    }

    /// After a round ends, the guesser draws next.
    var isNextTurnMine: Bool {
        guard let round, let userID = currentUserID else { return false }
        return round.guesserUserID == userID
    }

    /// The very first turn of a new game has no drawing to guess before it.
    var isFirstTurn: Bool {
        state?.game?.turnNumber == 1
    }

    /// The score panel of a solved round.
    var revealScore: DrawAndGuessRevealScore? {
        guard let reveal, let score, let round else { return nil }
        return DrawAndGuessRevealScore.make(
            reveal: reveal,
            score: score,
            iAmGuesser: round.guesserUserID == currentUserID
        )
    }

    func updateSpeedBonus() {
        let firstSeen = round.flatMap { $0.guesserFirstSeenAt ?? localFirstSeenAt[$0.id] }
        speedBonus = DrawAndGuessSpeedBonus.make(
            playStyle: settings?.playStyle,
            round: round,
            userID: currentUserID,
            firstSeenAt: firstSeen
        )
    }

    /// The bonus can still be earned right now.
    var speedBonusIsAvailable: Bool {
        speedBonus.isAvailable(at: dependencies.now())
    }

    /// Seconds of the speed bonus left, counted on the game's clock.
    func speedBonusRemaining() -> TimeInterval? {
        speedBonus.remaining(at: dependencies.now())
    }

    func updateReveal() {
        guard let userID = currentUserID, let round, round.isFinished, phase == .reveal else {
            reveal = nil
            return
        }
        let iAmGuesser = round.guesserUserID == userID
        let isSolved = round.state == .solved
        let outcome: DrawAndGuessReveal.Outcome = switch (isSolved, iAmGuesser) {
        case (true, true): .iSolvedIt
        case (true, false): .partnerSolvedIt
        case (false, true): .iGaveUp
        case (false, false): .partnerGaveUp
        }
        // A result that only exists on this phone has no confirmed bonus or time yet.
        let isConfirmed = round.localSolvedAt == nil && !pending.hasGiveUp(roundID: round.id)
        let bonus = isConfirmed ? round.speedBonus : nil
        reveal = DrawAndGuessReveal(
            outcome: outcome,
            word: round.word,
            difficulty: round.difficulty,
            wordPoints: round.points,
            speedBonus: isSolved ? bonus : 0,
            solveDuration: isSolved ? solveDuration(for: round) : nil,
            pointsForMe: isSolved ? round.points + (iAmGuesser ? bonus ?? 0 : 0) : 0,
            pointsForCouple: isSolved ? round.points : 0,
            attempts: round.attempts,
            isConfirmed: isConfirmed
        )
    }

    private func solveDuration(for round: DrawAndGuessRoundView) -> TimeInterval? {
        if let solveMs = round.solveMs {
            return TimeInterval(solveMs) / 1_000
        }
        guard let solvedAt = round.localSolvedAt,
              let first = round.guesserFirstSeenAt ?? localFirstSeenAt[round.id]
        else {
            return nil
        }
        return max(0, solvedAt.timeIntervalSince(first))
    }

    /// The save question shows on the reveal, and afterwards as a row on the
    /// screens where the next turn starts.
    func updateSavePrompt() {
        guard let userID = currentUserID, let round, round.isFinished,
              phase == .reveal || phase == .chooseWord || phase == .waitingForWord
        else {
            savePrompt = .hidden
            return
        }
        savePrompt = DrawAndGuessSavePrompt.make(
            round: round,
            userID: userID,
            hasSaveQueued: pending.hasSave(roundID: round.id),
            hasDrawing: finalDrawing != nil || round.drawingMediaAssetID != nil
        )
    }

    /// The finished drawing at the canonical size, from whichever source this phone
    /// has: the downloaded file, the drawer's own canvas, or the live room.
    var finalDrawing: DrawAndGuessFinalDrawing? {
        _ = loadedDrawingVersion
        guard let userID = currentUserID, let round else { return nil }
        if let downloadedDrawing, loadedAssetID != nil, loadedAssetID == round.drawingMediaAssetID {
            return DrawAndGuessFinalDrawing(drawing: downloadedDrawing)
        }
        if round.isDrawer(userID), boardRoundID == round.id, !board.isEmpty, board.canvasSide > 0 {
            return DrawAndGuessFinalDrawing(drawing: board.canonicalDrawing)
        }
        // A drawing queued on this phone, for a drawer who reopens the game offline.
        if let queued = pending.drawings.first(where: { $0.roundID == round.id }),
           let drawing = try? PKDrawing(data: queued.drawingData), !drawing.strokes.isEmpty {
            return DrawAndGuessFinalDrawing(drawing: drawing)
        }
        if let snapshot = liveSnapshots[round.id], !snapshot.strokes.isEmpty {
            return DrawAndGuessFinalDrawing(drawing: snapshot)
        }
        if !round.isDrawer(userID), let partnerCanvas = live?.partnerCanvasDrawing, !partnerCanvas.strokes.isEmpty {
            return DrawAndGuessFinalDrawing(drawing: partnerCanvas)
        }
        return nil
    }
}

/// A finished drawing at the canonical canvas size. Scale it to the canvas with
/// `fitted(toSide:)`.
struct DrawAndGuessFinalDrawing {
    let drawing: PKDrawing

    func fitted(toSide side: CGFloat) -> PKDrawing {
        DrawAndGuessCanvas.fitted(drawing, toSide: side)
    }
}
