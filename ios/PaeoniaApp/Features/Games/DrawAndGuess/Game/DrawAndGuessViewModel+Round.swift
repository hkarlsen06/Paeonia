import PencilKit
import SwiftUI

// What changes when the round changes: the guesser's tiles, the drawer's canvas,
// the speed bonus, and the numbers on the reveal.
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
                restoreHints(for: round)
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

    /// Any hint takes the speed bonus away, so the label and the line go.
    func updateSpeedBonus() {
        guard hintCount == 0 else {
            speedBonus = .hidden
            return
        }
        let firstSeen = round.flatMap { $0.guesserFirstSeenAt ?? localFirstSeenAt[$0.id] }
        speedBonus = DrawAndGuessSpeedBonus.make(
            playStyle: settings?.playStyle,
            round: round,
            userID: currentUserID,
            firstSeenAt: firstSeen
        )
    }

    /// What the screen promised for a correct guess made at `now`: the speed
    /// bonus tier it showed (0, 1 or 2), how long the guesser had looked at the
    /// drawing, and how many hints they used. It ignores the play style, because
    /// the server keeps every total. A hint always means no speed bonus.
    func speedBonusClaim(at now: Date) -> DrawAndGuessSolveClaim {
        let firstSeen = round.flatMap { $0.guesserFirstSeenAt ?? localFirstSeenAt[$0.id] }
        let bonus = DrawAndGuessSpeedBonus.make(
            playStyle: .against,
            round: round,
            userID: currentUserID,
            firstSeenAt: firstSeen
        )
        let solveMs = firstSeen.map { max(0, Int((now.timeIntervalSince($0) * 1_000).rounded())) }
        return DrawAndGuessSolveClaim(
            speedBonus: hintCount > 0 ? 0 : bonus.tier(at: now),
            solveMs: solveMs,
            hintsUsed: hintCount
        )
    }

    /// The points a correct guess earns for speed right now: 2, 1 or 0.
    var speedBonusTier: Int {
        speedBonus.tier(at: dependencies.now())
    }

    /// The bonus can still be earned right now.
    var speedBonusIsAvailable: Bool {
        speedBonusTier > 0
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
        // A result that only exists on this phone carries the bonuses the phone
        // promised. The server's numbers replace them when the result arrives.
        let isConfirmed = round.localSolvedAt == nil && !pending.hasGiveUp(roundID: round.id)
        let bonuses = iAmGuesser ? round.speedBonus + round.firstTryBonus : 0
        reveal = DrawAndGuessReveal(
            outcome: outcome,
            word: round.word,
            difficulty: round.difficulty,
            wordPoints: round.points,
            speedBonus: isSolved ? round.speedBonus : 0,
            firstTryBonus: isSolved ? round.firstTryBonus : 0,
            hintsUsed: isSolved ? round.hintsUsed : 0,
            personalBest: isSolved && isConfirmed && round.personalBest,
            reaction: round.guesserReaction,
            solveDuration: isSolved ? solveDuration(for: round) : nil,
            pointsForMe: isSolved ? round.points + bonuses : 0,
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

    /// The language to name above the answer while guessing, when it differs
    /// from the app's language. It follows the couple's setting, as the tiles do.
    var guessLanguageNotice: GameLanguage? {
        guard let round, let language = settings?.language else { return nil }
        return GameLanguage.guessNotice(game: language, app: .app, difficulty: round.difficulty)
    }

    /// The drawing the drawer sent or queued, which can no longer change: the
    /// downloaded file or the drawing queued on this phone. A live room can miss
    /// a stroke still on its way, and the canvas can still change.
    var submittedDrawing: DrawAndGuessFinalDrawing? {
        _ = loadedDrawingVersion
        guard let round else { return nil }
        if let downloadedDrawing, loadedAssetID != nil, loadedAssetID == round.drawingMediaAssetID {
            return DrawAndGuessFinalDrawing(drawing: downloadedDrawing)
        }
        // A drawing queued on this phone, for a drawer who reopens the game offline.
        if let queued = pending.drawings.first(where: { $0.roundID == round.id }) {
            if decodedQueuedDrawing?.data != queued.drawingData {
                decodedQueuedDrawing = (try? PKDrawing(data: queued.drawingData)).map { (queued.drawingData, $0) }
            }
            if let drawing = decodedQueuedDrawing?.drawing, !drawing.strokes.isEmpty {
                return DrawAndGuessFinalDrawing(drawing: drawing)
            }
        }
        return nil
    }
}

/// What the screen showed when the guesser made the correct guess.
struct DrawAndGuessSolveClaim: Equatable {
    /// The speed bonus tier on screen: 2, 1 or 0.
    let speedBonus: Int
    /// Milliseconds since the guesser first saw the drawing, on this phone's clock.
    let solveMs: Int?
    let hintsUsed: Int
}

/// A finished drawing at the canonical canvas size.
struct DrawAndGuessFinalDrawing {
    let drawing: PKDrawing
}
