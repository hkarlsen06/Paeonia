import Foundation

// The board on screen: which moves it shows, the replay of the partner's moves
// one at a time, the outcome's beats, and the ending of the last game when this
// person missed it.
extension BoardGameViewModel {
    /// The game the board is heading to: the missed ending while it shows,
    /// otherwise the current game.
    private var target: (gameNumber: Int, moves: [Int])? {
        if isShowingMissedEnding, let ending = missedEnding {
            return (ending.gameNumber, ending.moves)
        }
        return snapshot.map { ($0.gameNumber, $0.moves) }
    }

    var missedEnding: RemoteBoardGameEnding? {
        isShowingMissedEnding ? snapshot?.previous : nil
    }

    /// Moves the board on screen toward the game. The first time, the partner's
    /// moves since this phone last showed the game replay. A game that moved on
    /// in a way the board can't follow, such as a new game or a refused move,
    /// shows as it is.
    func advanceDisplay(to snapshot: BoardGameSnapshot<Board>, userID: UUID) {
        guard !isShowingMissedEnding else { return }
        if !hasDisplay {
            hasDisplay = true
            if showMissedEndingAtOpen(snapshot, userID: userID) {
                return
            }
            let start = Self.replayStart(of: snapshot, shown: document.shown[kind.rawValue], userID: userID)
            show(
                gameNumber: snapshot.gameNumber,
                moves: Array(snapshot.moves.prefix(start)),
                firstUserID: snapshot.firstUserID,
                userID: userID
            )
        }
        if keepEndingOnScreen(snapshot) {
            return
        }
        guard displayedGameNumber == snapshot.gameNumber, snapshot.moves.starts(with: displayedMoves) else {
            showAsItIs(snapshot, userID: userID)
            return
        }
        if displayedMoves.count < snapshot.moves.count {
            startReplay()
        } else if !isReplaying {
            settle()
        }
    }

    /// The last game ended past where this phone left it, so its ending replays
    /// before the new game.
    private func showMissedEndingAtOpen(_ snapshot: BoardGameSnapshot<Board>, userID: UUID) -> Bool {
        guard let previous = snapshot.previous, let shown = document.shown[kind.rawValue],
              shown.gameNumber == previous.gameNumber, shown.moveCount < previous.moves.count
        else { return false }
        isShowingMissedEnding = true
        show(
            gameNumber: previous.gameNumber,
            moves: Array(previous.moves.prefix(shown.moveCount)),
            firstUserID: previous.firstUserID,
            userID: userID
        )
        startReplay()
        return true
    }

    /// The game on screen ended, and the partner started the next one before
    /// this phone finished showing the ending, or while it shows. The ending
    /// plays and stays until "Continue". "Play again" on this phone resets the
    /// display first, so it never lands here.
    private func keepEndingOnScreen(_ snapshot: BoardGameSnapshot<Board>) -> Bool {
        guard displayedGameNumber != snapshot.gameNumber, let previous = snapshot.previous,
              previous.gameNumber == displayedGameNumber, previous.moves.starts(with: displayedMoves)
        else { return false }
        isShowingMissedEnding = true
        if result != nil {
            result = makeResult()
        }
        if displayedMoves.count < previous.moves.count {
            startReplay()
        } else if !isReplaying {
            // Stages the outcome once. One already on its way keeps going.
            settle()
        }
        updateScreen()
        return true
    }

    /// Where the replay starts when the board first shows: where this phone
    /// left the game, or else after this person's own last move.
    nonisolated static func replayStart(
        of snapshot: BoardGameSnapshot<Board>,
        shown: BoardGameShownPosition?,
        userID: UUID
    ) -> Int {
        if let shown, shown.gameNumber == snapshot.gameNumber {
            return min(shown.moveCount, snapshot.moves.count)
        }
        guard let movers = Board.movers(snapshot.moves) else { return snapshot.moves.count }
        let me = snapshot.player(for: userID)
        guard let last = movers.lastIndex(of: me) else { return 0 }
        return last + 1
    }

    /// "Continue" under a missed ending: on to the current game.
    func continueAfterMissedEnding() {
        guard isShowingMissedEnding else { return }
        markShown()
        isShowingMissedEnding = false
        hasDisplay = false
        replayTask?.cancel()
        replayTask = nil
        isReplaying = false
        outcomeTask?.cancel()
        showsOutcome = false
        result = nil
        isResultCollapsed = false
        stagedOutcomeGame = nil
        lastMove = nil
        PaeoniaHaptics.selection()
        recompute()
    }

    /// A tap on the board while it replays or celebrates: jump to the end.
    func skipToEnd() {
        guard isReplaying || (showsOutcome && result == nil), let target else { return }
        replayTask?.cancel()
        replayTask = nil
        isReplaying = false
        outcomeTask?.cancel()
        outcomeTask = nil
        if let board = Board.replay(target.moves) {
            self.board = board
            displayedMoves = target.moves
        }
        lastMove = nil
        if board.outcome != nil {
            stagedOutcomeGame = displayedGameNumber
            showsOutcome = true
            result = makeResult()
        }
        markShown()
        updateScreen()
    }

    // MARK: - Showing moves

    func show(gameNumber: Int, moves: [Int], firstUserID: UUID, userID: UUID) {
        if gameNumber != displayedGameNumber {
            showsOutcome = false
            result = nil
            isResultCollapsed = false
            stagedOutcomeGame = nil
        }
        displayedGameNumber = gameNumber
        displayedMoves = moves
        board = Board.replay(moves) ?? .initial
        me = firstUserID == userID ? .one : .two
        lastMove = nil
    }

    private func showAsItIs(_ snapshot: BoardGameSnapshot<Board>, userID: UUID) {
        replayTask?.cancel()
        replayTask = nil
        isReplaying = false
        outcomeTask?.cancel()
        outcomeTask = nil
        show(gameNumber: snapshot.gameNumber, moves: snapshot.moves, firstUserID: snapshot.firstUserID, userID: userID)
        if board.outcome == nil {
            showsOutcome = false
            result = nil
            stagedOutcomeGame = nil
        }
        settle(animated: false)
    }

    /// Shows one move on the board. The board animates it.
    @discardableResult
    func step(_ move: Int) -> BoardMoveEvent? {
        let mover = board.next
        guard let after = board.applying(move) else { return nil }
        board = after
        displayedMoves.append(move)
        let event = BoardMoveEvent(number: displayedMoves.count, move: move, player: mover, isMine: mover == me)
        lastMove = event
        return event
    }

    private func startReplay() {
        guard replayTask == nil else { return }
        isReplaying = true
        updateScreen()
        replayTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let target, target.gameNumber == displayedGameNumber,
                      target.moves.starts(with: displayedMoves), displayedMoves.count < target.moves.count
                else { break }
                guard let event = step(target.moves[displayedMoves.count]) else { break }
                updateScreen()
                try? await sleep(moveDuration(event))
            }
            guard let self, !Task.isCancelled else { return }
            replayTask = nil
            isReplaying = false
            settle()
        }
    }

    func moveDuration(_ event: BoardMoveEvent) -> Duration {
        if prefersReducedMotion {
            return .milliseconds(250)
        }
        return event.isMine ? timing.mine : timing.partner
    }

    /// The board has caught up. A finished game gets its outcome beats once.
    /// Otherwise this phone remembers how far it showed the game.
    func settle(animated: Bool = true) {
        updateScreen()
        guard board.outcome != nil else {
            markShown()
            return
        }
        stageOutcome(animated: animated, after: .zero)
    }

    /// The outcome's beats after the last move landed: the board's highlight at
    /// 0.15 s, the haptic at 0.70 s and the result panel at 1.10 s. Reduce
    /// Motion and a game already celebrated show the settled state at once.
    func stageOutcome(animated: Bool, after delay: Duration) {
        guard stagedOutcomeGame != displayedGameNumber else { return }
        stagedOutcomeGame = displayedGameNumber
        let isWin = board.outcome?.winner != nil
        let alreadyShown = document.shown[kind.rawValue].map {
            $0.gameNumber == displayedGameNumber && $0.moveCount >= displayedMoves.count
        } ?? false
        markShown()
        guard animated, !alreadyShown, !prefersReducedMotion else {
            if animated, !alreadyShown {
                Self.outcomeHaptic(isWin: isWin)
            }
            showsOutcome = true
            result = makeResult()
            updateScreen()
            return
        }
        outcomeTask?.cancel()
        outcomeTask = Task { [weak self] in
            guard let self else { return }
            try? await sleep(delay + .milliseconds(150))
            guard !Task.isCancelled else { return }
            showsOutcome = true
            updateScreen()
            try? await sleep(.milliseconds(550))
            guard !Task.isCancelled else { return }
            Self.outcomeHaptic(isWin: isWin)
            try? await sleep(.milliseconds(400))
            guard !Task.isCancelled else { return }
            result = makeResult()
            updateScreen()
        }
    }

    private static func outcomeHaptic(isWin: Bool) {
        if isWin {
            PaeoniaHaptics.answerRevealed()
        } else {
            PaeoniaHaptics.partnerDrawingReceived()
        }
    }

    func makeResult() -> BoardGameResultContent? {
        guard let outcome = board.outcome, let snapshot else { return nil }
        let winner: BoardGameWinner = if let player = outcome.winner {
            player == me ? .me : .partner
        } else {
            .draw
        }
        let stake = isShowingMissedEnding ? missedEnding?.stake : snapshot.stake
        return BoardGameResultContent(
            winner: winner,
            playStyle: overview?.settings?.playStyle ?? .against,
            stake: stake,
            myWins: snapshot.myWins,
            partnerWins: snapshot.partnerWins,
            gamesFinished: snapshot.gamesFinished,
            isMissedEnding: isShowingMissedEnding
        )
    }

    /// Remembers how far this phone showed the game, so the next visit replays
    /// only what is new.
    func markShown() {
        guard let userID = currentUserID, hasDisplay else { return }
        let position = BoardGameShownPosition(gameNumber: displayedGameNumber, moveCount: displayedMoves.count)
        guard document.shown[kind.rawValue] != position else { return }
        document.shown[kind.rawValue] = position
        let cache = dependencies.boardGamesCache
        let kind = kind
        Task { await cache.markShown(position, kind: kind, ownerUserID: userID) }
    }
}
