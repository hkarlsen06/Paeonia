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
            restoreLiveSnapshot(userID: userID)
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
        unlockRefusedCorrectGuess()

        if let round, round.isDrawer(userID), !round.isFinished {
            syncBoard(for: round, userID: userID)
        }
    }

    /// A correct guess that the server refused for good left the round open with
    /// the right word in the slots, which then take no tile. They empty, so the
    /// person can guess again.
    func unlockRefusedCorrectGuess() {
        guard let round, phase.allowsGuessing, tilesRoundID == round.id, slots.status == .correct,
              queuingCorrectGuessRoundID != round.id
        else { return }
        slots.clear()
    }

    /// Fills the canvas when the drawer's round starts, and again when a refused
    /// drawing comes back to it. The refusal saves the drawing as the draft.
    private func syncBoard(for round: DrawAndGuessRoundView, userID: UUID) {
        let isBackFromSending = boardSentRoundID == round.id && !round.isDrawingSent
            && dependencies.drawingStore.draft(ownerUserID: userID, roundID: round.id) != nil
        if boardRoundID != round.id || isBackFromSending {
            boardRoundID = round.id
            board.reset()
            if let saved = startingDrawing(for: round, userID: userID) {
                board.restore(canonical: saved)
            }
            live?.drawingReplacedFromCode(board.drawing)
        }
        boardSentRoundID = round.isDrawingSent ? round.id : nil
    }

    /// What the canvas starts with: this round's draft, the drawing queued for
    /// it, or the drawing made for a word the server refused. The refused drawing
    /// becomes this round's draft first, so closing the app now does not lose it.
    private func startingDrawing(for round: DrawAndGuessRoundView, userID: UUID) -> PKDrawing? {
        let store = dependencies.drawingStore
        if let data = store.draft(ownerUserID: userID, roundID: round.id), let draft = try? PKDrawing(data: data) {
            return draft
        }
        if let queued = pending.drawings.last(where: { $0.roundID == round.id }),
           let drawing = try? PKDrawing(data: queued.drawingData) {
            return drawing
        }
        guard let data = store.rescuedDrawing(ownerUserID: userID), let rescued = try? PKDrawing(data: data) else {
            return nil
        }
        store.saveDraft(data, ownerUserID: userID, roundID: round.id)
        store.removeRescuedDrawing(ownerUserID: userID)
        return rescued
    }

    /// A live snapshot kept on disk from before a relaunch, for the reveal while
    /// the drawer's sent drawing is not on this phone.
    private func restoreLiveSnapshot(userID: UUID) {
        guard let round, !round.isDrawer(userID), liveSnapshots[round.id] == nil,
              let data = dependencies.drawingStore.liveSnapshot(ownerUserID: userID, roundID: round.id),
              let snapshot = try? PKDrawing(data: data)
        else { return }
        liveSnapshots[round.id] = snapshot
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

    /// What the screen promised for a correct guess made at `now`: whether the
    /// bonus was still available and how long the guesser had looked at the
    /// drawing. It ignores the play style, because the server keeps every total.
    func speedBonusClaim(at now: Date) -> (speedBonus: Bool, solveMs: Int?) {
        let firstSeen = round.flatMap { $0.guesserFirstSeenAt ?? localFirstSeenAt[$0.id] }
        let bonus = DrawAndGuessSpeedBonus.make(
            playStyle: .against,
            round: round,
            userID: currentUserID,
            firstSeenAt: firstSeen
        )
        let solveMs = firstSeen.map { max(0, Int((now.timeIntervalSince($0) * 1_000).rounded())) }
        return (bonus.isAvailable(at: now), solveMs)
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
        // The server's answer may still be on its way. Until it arrives, a "not now"
        // from this phone keeps the question closed.
        if savePrompt == .ask, declinedSaveRoundIDs.contains(round.id) {
            savePrompt = .hidden
        }
    }

    /// The finished drawing at the canonical size, from whichever source this phone
    /// has: the drawer's final drawing, or what the live room showed.
    var finalDrawing: DrawAndGuessFinalDrawing? {
        guard let userID = currentUserID, let round else { return nil }
        if let submitted = submittedDrawing {
            return submitted
        }
        if round.isDrawer(userID), boardRoundID == round.id, !board.isEmpty, board.canvasSide > 0 {
            return DrawAndGuessFinalDrawing(drawing: board.canonicalDrawing)
        }
        if let snapshot = liveSnapshots[round.id], !snapshot.strokes.isEmpty {
            return DrawAndGuessFinalDrawing(drawing: snapshot)
        }
        if !round.isDrawer(userID), let partnerCanvas = live?.partnerCanvasDrawing, !partnerCanvas.strokes.isEmpty {
            return DrawAndGuessFinalDrawing(drawing: partnerCanvas)
        }
        return nil
    }

    /// The drawing the drawer sent or queued, which can no longer change: the
    /// downloaded file or the drawing queued on this phone. A live room can miss
    /// a stroke still on its way, and the canvas can still change, so Memories
    /// only ever gets this one.
    var submittedDrawing: DrawAndGuessFinalDrawing? {
        _ = loadedDrawingVersion
        guard let round else { return nil }
        if let downloadedDrawing, loadedAssetID != nil, loadedAssetID == round.drawingMediaAssetID {
            return DrawAndGuessFinalDrawing(drawing: downloadedDrawing)
        }
        // A drawing queued on this phone, for a drawer who reopens the game offline.
        if let queued = pending.drawings.first(where: { $0.roundID == round.id }),
           let drawing = try? PKDrawing(data: queued.drawingData), !drawing.strokes.isEmpty {
            return DrawAndGuessFinalDrawing(drawing: drawing)
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
