import Foundation
@testable import PaeoniaApp

/// The moves of a turn: picking a word, sending the drawing, guessing and giving up,
/// and what the two players do once the round is over.
extension SimServer {
    /// What the guesser's phone claims about its own solve.
    private struct GuessClaim {
        let speedBonus: Int?
        let solveMs: Int?
        let hintsUsed: Int?
    }

    // MARK: - The turn

    func pickWord(user: UUID, _ pick: GamePickWordPayload, operation: SyncClientOperation) throws -> RemotePickedWord {
        let customWord = pick.choice == .custom ? try Self.normalizeCustomWord(pick.word) : nil
        let seenWordID = pick.choice == .custom ? "" : (pick.wordID ?? "")
        let request = [
            "pick_draw_word", pick.gameID.uuidString, pick.roundID.uuidString, pick.choice.rawValue,
            customWord ?? "", seenWordID,
        ]
        return try runOperation(user, operation, request: request) {
            try startRound(user: user, pick: pick, customWord: customWord, seenWordID: seenWordID)
        }
    }

    private func requireOpenPick(user: UUID, pick: GamePickWordPayload) throws -> Game {
        guard let game, game.id == pick.gameID else { throw noAccess() }
        guard game.turnUser == user else { throw Self.fail("42501", "it is not your turn") }
        guard game.state == .choosingWord else {
            throw Self.fail("23514", "a word was already chosen for this turn")
        }
        guard roundIndex(pick.roundID) == nil else {
            throw Self.fail("23505", "duplicate key value violates unique constraint \"game_moves_pkey\"")
        }
        return game
    }

    private func startRound(
        user: UUID,
        pick: GamePickWordPayload,
        customWord: String?,
        seenWordID: String
    ) throws -> RemotePickedWord {
        var game = try requireOpenPick(user: user, pick: pick)
        let word: String
        let wordID: String?
        if let customWord {
            word = customWord
            wordID = nil
        } else {
            guard let choice = game.choices?.first(where: { $0.difficulty == pick.choice }) else {
                throw Self.fail("23514", "word choice is not available")
            }
            guard choice.wordID == seenWordID else { throw Self.fail("23514", "word choice is out of date") }
            word = choice.word
            wordID = choice.wordID
        }
        let points = [DrawAndGuessDifficulty.easy: 1, .medium: 2, .hard: 3, .custom: 2][pick.choice] ?? 2
        rounds.append(Round(
            id: pick.roundID,
            number: game.turnNumber,
            drawer: user,
            guesser: partner(of: user),
            state: .drawing,
            difficulty: pick.choice,
            wordID: wordID,
            word: word,
            points: points,
            startedAt: now
        ))
        game.state = .drawing
        game.currentRoundID = pick.roundID
        game.choices = nil
        patch(&game)
        self.game = game
        changed()
        return RemotePickedWord(
            roundID: pick.roundID,
            roundNumber: game.turnNumber,
            difficulty: pick.choice,
            word: word,
            points: points
        )
    }

    func submitDrawing(
        user: UUID,
        roundID: UUID,
        assetID: UUID,
        operation: SyncClientOperation
    ) throws -> RemoteSubmitDrawingResult {
        try runOperation(user, operation, request: ["submit_drawing", roundID.uuidString, assetID.uuidString]) {
            try storeDrawing(user: user, roundID: roundID, assetID: assetID)
        }
    }

    private func requireUsableDrawing(user: UUID, round: Round, assetID: UUID) throws {
        guard round.drawer == user else { throw Self.fail("42501", "only the drawer can send the drawing") }
        guard round.drawingAssetID == nil else {
            throw Self.fail("23505", "the drawing for this round was already sent")
        }
        guard let asset = assets[assetID],
              asset.owner == user,
              asset.roundID == round.id,
              !asset.queuedForDelete
        else {
            throw Self.fail("23514", "game drawing asset is not usable")
        }
        if rounds.contains(where: { $0.drawingAssetID == assetID }) {
            throw Self.fail(
                "23505",
                "duplicate key value violates unique constraint \"game_moves_drawing_media_asset_id_unique_idx\""
            )
        }
    }

    private func storeDrawing(user: UUID, roundID: UUID, assetID: UUID) throws -> RemoteSubmitDrawingResult {
        let index = try requireRound(roundID)
        var round = rounds[index]
        try requireUsableDrawing(user: user, round: round, assetID: assetID)
        let wasDrawing = round.state == .drawing
        round.drawingAssetID = assetID
        round.submittedAt = now
        if wasDrawing {
            round.state = .guessing
        }
        rounds[index] = round
        if wasDrawing, var game {
            game.state = .guessing
            game.turnUser = round.guesser
            game.turnStartedAt = now
            patch(&game)
            self.game = game
        }
        changed()
        return RemoteSubmitDrawingResult(roundID: roundID, roundState: round.state, drawingSubmittedAt: now)
    }

    func markSeen(user: UUID, roundID: UUID) throws -> RemoteMarkSeenResult {
        let index = try requireRound(roundID)
        var round = rounds[index]
        guard round.guesser == user else { throw Self.fail("42501", "only the guesser can see this drawing") }
        guard !round.state.isFinished, round.firstSeenAt == nil else {
            return RemoteMarkSeenResult(guesserFirstSeenAt: round.firstSeenAt)
        }
        round.firstSeenAt = now
        rounds[index] = round
        changed()
        return RemoteMarkSeenResult(guesserFirstSeenAt: now)
    }

    static let maxStoredSolveMs = 30 * 24 * 60 * 60 * 1_000

    func submitGuess( // swiftlint:disable:this function_parameter_count
        user: UUID,
        roundID: UUID,
        guess rawGuess: String,
        speedBonus: Int?,
        solveMs: Int?,
        hintsUsed: Int?,
        operation: SyncClientOperation
    ) throws -> RemoteGuessResult {
        let guess = Self.normalizeWordText(rawGuess)
        let claim = GuessClaim(speedBonus: speedBonus, solveMs: solveMs, hintsUsed: hintsUsed)
        try Self.validate(guess: guess, claim: claim)
        let request = [
            "submit_guess", roundID.uuidString, guess,
            speedBonus.map { "\($0)" } ?? "null", solveMs.map { "\($0)" } ?? "null",
            hintsUsed.map { "\($0)" } ?? "null",
        ]
        return try runOperation(user, operation, request: request) {
            try applyGuess(user: user, roundID: roundID, guess: guess, claim: claim)
        }
    }

    private static func validate(guess: String, claim: GuessClaim) throws {
        guard !guess.isEmpty, guess.count <= 40 else { throw fail("23514", "guess must be 1 to 40 characters") }
        if let speedBonus = claim.speedBonus, !(0...2).contains(speedBonus) {
            throw fail("23514", "speed bonus must be 0, 1, or 2")
        }
        if let solveMs = claim.solveMs, solveMs < 0 {
            throw fail("23514", "solve time must be a number of milliseconds from 0 up")
        }
        if let hintsUsed = claim.hintsUsed, hintsUsed < 0 {
            throw fail("23514", "hints used must be a whole number from 0 up")
        }
    }

    private func applyGuess(user: UUID, roundID: UUID, guess: String, claim: GuessClaim) throws -> RemoteGuessResult {
        let index = try requireRound(roundID)
        var round = rounds[index]
        guard round.guesser == user else { throw Self.fail("42501", "only the guesser can guess") }
        guard !round.state.isFinished else { throw Self.fail("23514", "this round is already finished") }
        let correct = guess == round.word
        // A hint can reveal at most all letters but one.
        if correct, let hintsUsed = claim.hintsUsed, hintsUsed > round.word.filter({ $0 != " " }).count - 1 {
            throw Self.fail("23514", "hints used is more than the word allows")
        }
        let attempt = RemoteDrawAndGuessAttempt(
            id: UUID(),
            userID: user,
            text: guess,
            correct: correct,
            createdAt: now
        )
        round.attempts.append(attempt)
        rounds[index] = round
        guard correct else {
            changed()
            return RemoteGuessResult(
                guessID: attempt.id,
                correct: false,
                roundState: round.state,
                points: 0,
                speedBonus: 0,
                firstTryBonus: 0,
                hintsUsed: 0,
                personalBest: false,
                solveMs: nil,
                createdAt: now
            )
        }
        return solveRound(at: index, by: user, attempt: attempt, claim: claim)
    }

    /// A correct guess ends the round, scores it and starts the next turn for the guesser.
    private func solveRound(
        at index: Int,
        by user: UUID,
        attempt: RemoteDrawAndGuessAttempt,
        claim: GuessClaim
    ) -> RemoteGuessResult {
        var round = rounds[index]
        let isFirstAttempt = round.attempts.count == 1
        let hints = claim.hintsUsed ?? 0
        let scored = scoreSolve(round)
        let bonus = hints > 0 ? 0 : (claim.speedBonus ?? scored.bonus)
        let firstTry = hints == 0 && isFirstAttempt ? 1 : 0
        let storedSolveMs = claim.solveMs.map { min($0, Self.maxStoredSolveMs) } ?? scored.solveMs
        let best = hints == 0 && storedSolveMs.map { isPersonalBest(guesser: user, solveMs: $0) } == true
        round.state = .solved
        round.endedAt = now
        round.solveMs = storedSolveMs
        round.speedBonus = bonus
        round.firstTryBonus = firstTry
        round.hintsUsed = hints
        round.personalBest = best
        rounds[index] = round
        if var game {
            game.points[round.drawer, default: 0] += round.points
            game.points[user, default: 0] += round.points + bonus + firstTry
            game.shared += round.points
            beginTurn(&game, drawer: user)
            self.game = game
        }
        changed()
        return RemoteGuessResult(
            guessID: attempt.id,
            correct: true,
            roundState: .solved,
            points: round.points,
            speedBonus: bonus,
            firstTryBonus: firstTry,
            hintsUsed: hints,
            personalBest: best,
            solveMs: storedSolveMs,
            createdAt: now
        )
    }

    /// `scoreSolve`: 2 within 15 seconds of the first look, 1 within 30, else 0.
    private func scoreSolve(_ round: Round) -> (bonus: Int, solveMs: Int?) {
        guard let seen = round.firstSeenAt else { return (0, nil) }
        let solveMs = max(0, Int(now.timeIntervalSince(seen) * 1_000))
        return (solveMs <= 15_000 ? 2 : solveMs <= 30_000 ? 1 : 0, solveMs)
    }

    /// `isPersonalBest`: faster than every earlier hint-free solve by the guesser, and there is one.
    private func isPersonalBest(guesser: UUID, solveMs: Int) -> Bool {
        let earlier = rounds.filter {
            $0.guesser == guesser && $0.state == .solved && $0.hintsUsed == 0 && $0.solveMs != nil
        }
        return !earlier.isEmpty && earlier.allSatisfy { solveMs < ($0.solveMs ?? 0) }
    }

    func giveUp(user: UUID, roundID: UUID, operation: SyncClientOperation) throws -> RemoteGiveUpResult {
        try runOperation(user, operation, request: ["give_up_round", roundID.uuidString]) {
            let index = try requireRound(roundID)
            var round = rounds[index]
            guard round.guesser == user else { throw Self.fail("42501", "only the guesser can give up") }
            guard !round.state.isFinished else { throw Self.fail("23514", "this round is already finished") }
            round.state = .missed
            round.endedAt = now
            rounds[index] = round
            if var game {
                beginTurn(&game, drawer: user)
                self.game = game
            }
            changed()
            return RemoteGiveUpResult(roundID: roundID, roundState: .missed)
        }
    }

    // MARK: - After the round

    /// `mark_round_result_seen`: the first time wins, for the caller's own role.
    func markResultSeen(user: UUID, roundID: UUID) throws -> RemoteResultSeenResult {
        let index = try requireRound(roundID)
        var round = rounds[index]
        guard round.state.isFinished else { throw Self.fail("23514", "the round is not finished yet") }
        let seenAt: Date
        var isFirstTime = false
        if round.drawer == user {
            isFirstTime = round.drawerSeenAt == nil
            seenAt = round.drawerSeenAt ?? now
            round.drawerSeenAt = seenAt
        } else if round.guesser == user {
            isFirstTime = round.guesserSeenAt == nil
            seenAt = round.guesserSeenAt ?? now
            round.guesserSeenAt = seenAt
        } else {
            throw Self.fail("42501", "only the drawer or the guesser can see this result")
        }
        if isFirstTime {
            rounds[index] = round
            changed()
        }
        return RemoteResultSeenResult(roundID: roundID, resultSeenAt: seenAt)
    }

    /// `set_round_reaction`: the guesser's reaction to a finished round. The last write wins.
    func setReaction(user: UUID, roundID: UUID, reaction: DrawAndGuessReaction?) throws -> RemoteReactionResult {
        let index = try requireRound(roundID)
        guard rounds[index].guesser == user else { throw Self.fail("42501", "only the guesser can react") }
        guard rounds[index].state.isFinished else { throw Self.fail("23514", "the round is not finished yet") }
        if rounds[index].reaction != reaction {
            rounds[index].reaction = reaction
            changed()
        }
        return RemoteReactionResult(roundID: roundID, guesserReaction: reaction)
    }
}
