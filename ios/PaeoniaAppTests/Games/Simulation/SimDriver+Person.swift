import Foundation
import PencilKit
@testable import PaeoniaApp

/// What a person does on a phone, one action per step, and the checks that each move
/// reached the queue or showed a notice.
extension SimDriver {
    func act(as phone: SimPhone) async {
        guard let viewModel = prepareToAct(phone) else { return }
        switch viewModel.phase {
        case .chooseWord:
            await chooseWord(phone, viewModel)
        case .drawing:
            await draw(phone, viewModel)
        case .waitingForDrawing, .watchingLive, .guessing:
            await guess(phone, viewModel)
        case .reveal:
            await reveal(phone, viewModel)
        case .waitingForGuess, .waitingForWord:
            idleOnWaitingScreen(phone, viewModel)
        case .waitingToSync:
            log.add("\(phone.name) try again")
            Task { await viewModel.retrySending() }
        case .needsSetup, .loading, .preparing:
            recoverStartup(phone, viewModel)
        }
    }

    /// Gets the phone to a state where a person could act on the game screen, or does the
    /// one step that gets it closer. Returns the screen's view model once it is ready.
    private func prepareToAct(_ phone: SimPhone) -> DrawAndGuessViewModel? {
        guard phone.isAlive else {
            phone.launch()
            return nil
        }
        guard phone.isForeground else {
            phone.moveToForeground()
            return nil
        }
        guard phone.isScreenOpen, let viewModel = phone.viewModel else {
            if random.chance(0.15), let games = phone.games {
                log.add("\(phone.name) hub refresh")
                Task { await games.refresh() }
            } else {
                phone.openScreen()
            }
            return nil
        }
        return viewModel
    }

    private func idleOnWaitingScreen(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) {
        if viewModel.invite == .available, random.chance(0.15) {
            log.add("\(phone.name) invite")
            Task { await viewModel.sendInvite() }
        } else if random.chance(0.2) {
            phone.closeScreen()
        }
    }

    private func recoverStartup(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) {
        switch viewModel.phase {
        case .needsSetup:
            if let games = phone.games {
                Task { await games.finishSetup() }
            }
        default:
            if viewModel.startFailed {
                Task { await viewModel.retryStart() }
            }
        }
    }

    private func expectMove(
        _ phone: SimPhone,
        kind: SyncPendingOperationKind,
        _ action: String,
        shows expected: Set<DrawAndGuessPhase> = [],
        _ body: () async -> Void
    ) async {
        guard !isBurst else {
            await body()
            return
        }
        let before = await phone.pending.ledger.filter { $0.kind == kind }.count
        let noticesBefore = phone.notices.count
        await body()
        await pump()
        let after = await phone.pending.ledger.filter { $0.kind == kind }.count
        if after == before {
            let noticed = phone.notices.dropFirst(noticesBefore).contains {
                $0 == .couldNotSaveMove || $0 == .drawingTooBig
            }
            if !noticed {
                failNow("\(phone.name) \(action) made no move and showed no notice")
            }
            return
        }
        // Local first: the screen shows the move at once, online or not.
        if !expected.isEmpty, phone.notices.count == noticesBefore, let phase = phone.activeViewModel?.phase,
           !expected.contains(phase) {
            failNow("\(phone.name) \(action) left the screen in \(phase), expected \(expected)")
        }
    }

    private func failNow(_ message: String) {
        if pendingFailure == nil {
            pendingFailure = SimFailure(message: message)
        }
    }

    private func chooseWord(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) async {
        if !viewModel.choices.isEmpty, random.chance(0.85) {
            let choice = random.pick(viewModel.choices)
            log.add("\(phone.name) pick \(choice.word) (\(choice.difficulty.rawValue))")
            await expectMove(phone, kind: .pickDrawWord, "pick", shows: [.drawing]) {
                await viewModel.chooseWord(choice)
            }
        } else {
            let custom = random.pick([
                "flying cat", "  Dog At   Mom ", "Brunost", "ab", "Æ Ø Å", "hot dog", "vaffel jern",
            ])
            viewModel.customWord = custom
            guard viewModel.customWordValidation.word != nil else { return }
            log.add("\(phone.name) pick custom '\(custom)'")
            await expectMove(phone, kind: .pickDrawWord, "custom pick", shows: [.drawing]) {
                await viewModel.chooseCustomWord()
            }
        }
    }

    private func draw(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) async {
        phone.updateScreens()
        guard let canvas = phone.canvas, let round = viewModel.round else { return }
        let board = viewModel.board
        if !board.isEmpty, random.chance(0.35), viewModel.canFinishDrawing {
            log.add("\(phone.name) done (\(board.drawing.strokes.count) strokes)")
            await expectMove(
                phone,
                kind: .submitGameDrawing,
                "done",
                shows: [.waitingForGuess, .reveal]
            ) { await viewModel.finishDrawing() }
            boardStrokes[phone.name] = nil
            drawnHere.insert(round.id)
            return
        }
        if !board.isEmpty, random.chance(0.06) {
            log.add("\(phone.name) erase a stroke")
            canvas.erase(strokeAt: random.int(0...(board.drawing.strokes.count - 1)))
        } else if !board.isEmpty, random.chance(0.03) {
            log.add("\(phone.name) clear")
            board.clear()
            canvas.sync()
        } else {
            let count = random.int(1...3)
            for _ in 0..<count {
                canvas.draw(SimStrokes.stroke(seed: &random, side: canvas.side))
            }
            log.add("\(phone.name) draw \(count) strokes")
        }
        boardStrokes[phone.name] = (round.id, board.drawing.strokes.count)
    }

    private func guess(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) async {
        guard !viewModel.isShowingWrongGuess, let round = viewModel.round else { return }
        let canSee = viewModel.phase != .waitingForDrawing
        let action = random.weighted([
            ("right", canSee ? 3.0 : 0.5),
            ("wrong", 4.5),
            ("showMe", 0.6),
            ("hint", viewModel.canShowLetter ? 1.2 : 0),
            ("wait", 1.5),
        ])
        switch action {
        case "right", "wrong":
            await typeGuess(phone, viewModel, round: round, isRight: action == "right")
        case "hint":
            viewModel.showLetter()
            hinted["\(phone.name)-\(round.id)"] = viewModel.slots.hintedIndexes
            log.add("\(phone.name) hint \(viewModel.slots.hintedIndexes) on \(round.id.uuidString.prefix(6))")
        case "showMe":
            log.add("\(phone.name) show me")
            await expectMove(phone, kind: .giveUpGameRound, "show me", shows: [.reveal]) {
                await viewModel.giveUp()
            }
        default:
            if random.chance(0.3) {
                viewModel.setFastForward(true)
                viewModel.setFastForward(false)
            }
        }
    }

    /// Fills the open slots with the right letters or with random ones, tile by tile.
    private func typeGuess(
        _ phone: SimPhone,
        _ viewModel: DrawAndGuessViewModel,
        round: DrawAndGuessRoundView,
        isRight: Bool
    ) async {
        if viewModel.slots.slots.contains(where: { $0.tile != nil && !$0.isHint }) {
            viewModel.clearGuess()
        }
        // A hint locks its slot, so the person fills only the open ones.
        let open = viewModel.slots.slots.filter { !$0.isGap && $0.tile == nil }
        guard !viewModel.tiles.isEmpty, !open.isEmpty,
              let letters = pickTiles(for: open, in: viewModel, isRight: isRight)
        else { return }
        // The whole word as it will stand, hinted letters included.
        var standing = viewModel.slots.slots.map { $0.isGap ? Character(" ") : ($0.tile?.letter ?? "?") }
        for (slot, tile) in zip(open, letters) {
            standing[slot.id] = tile.letter
        }
        let word = String(standing)
        let isCorrect = word == viewModel.slots.answer
        if isCorrect {
            let claim = viewModel.speedBonusClaim(at: clock.now)
            promisedBonus[round.id] = claim.speedBonus
            promisedHints[round.id] = claim.hintsUsed
        }
        log.add("\(phone.name) guess \(word) on \(round.id.uuidString.prefix(6)) [\(viewModel.phase)]")
        await expectMove(phone, kind: .submitGameGuess, "guess", shows: isCorrect ? [.reveal] : []) {
            for tile in letters {
                viewModel.placeTile(tile)
            }
        }
    }

    /// One tile for each open slot, or nil when the right letter has no tile left.
    private func pickTiles(
        for open: [DrawAndGuessSlots.Slot],
        in viewModel: DrawAndGuessViewModel,
        isRight: Bool
    ) -> [DrawAndGuessTile]? {
        let tiles = viewModel.tiles
        var used = viewModel.slots.placedTileIDs
        var letters: [DrawAndGuessTile] = []
        if isRight {
            for slot in open {
                let letter = Array(viewModel.slots.answer)[slot.id]
                guard let tile = tiles.first(where: { $0.letter == letter && !used.contains($0.id) }) else {
                    return nil
                }
                used.insert(tile.id)
                letters.append(tile)
            }
        } else {
            var pool = tiles.filter { !used.contains($0.id) }
            for _ in open {
                let index = random.int(0...(pool.count - 1))
                letters.append(pool.remove(at: index))
            }
        }
        return letters
    }

    private func reveal(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) async {
        if let round = viewModel.round, round.guesserUserID == phone.userID, random.chance(0.35) {
            let reaction = random.pick(DrawAndGuessReaction.allCases)
            log.add("\(phone.name) react \(reaction.rawValue)")
            await expectMove(phone, kind: .setGameRoundReaction, "react") { await viewModel.react(reaction) }
            shownReactions[round.id, default: []].insert(viewModel.reveal?.reaction?.rawValue ?? "none")
            return
        } else {
            log.add("\(phone.name) continue")
            let roundID = viewModel.round?.id
            Task { await viewModel.continueFromReveal() }
            guard !isBurst else { return }
            await pump()
            if phone.activeViewModel === viewModel, viewModel.phase == .reveal, viewModel.round?.id == roundID {
                failNow("\(phone.name) continue did not leave the reveal")
            }
        }
    }
}
