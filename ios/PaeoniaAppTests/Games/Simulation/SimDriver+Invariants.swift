import Foundation
import PencilKit
@testable import PaeoniaApp

// The invariants the driver checks. `checkAlways` runs after every step, and
// `checkSettled` once the network is up and the queues have drained.
extension SimDriver {
    // MARK: - Invariants

    /// Checked after every step, also while offline.
    func checkAlways() throws {
        if let pendingFailure {
            throw pendingFailure
        }
        // A drawer looking at their own sent drawing never sees a blank square, even offline.
        for phone in phones {
            guard let viewModel = phone.activeViewModel, let round = viewModel.round,
                  viewModel.phase == .waitingForGuess || viewModel.phase == .reveal,
                  round.isDrawer(phone.userID), drawnHere.contains(round.id), !viewModel.isLoadingDrawing
            else { continue }
            if viewModel.finalDrawing?.drawing.strokes.isEmpty != false {
                throw SimFailure(message: "\(phone.name) shows a blank square for its own drawing of \(round.id.uuidString.prefix(6)) in \(viewModel.phase) (load failed \(viewModel.drawingLoadFailed))")
            }
        }
        for phone in phones {
            guard let viewModel = phone.activeViewModel, let record = boardStrokes[phone.name] else { continue }
            if viewModel.phase == .drawing, viewModel.round?.id == record.roundID, phone.canvas != nil,
               viewModel.board.drawing.strokes.count != record.count {
                throw SimFailure(message: "\(phone.name) draft lost: board has \(viewModel.board.drawing.strokes.count) strokes, drew \(record.count)")
            }
        }
    }

    private func fail(_ message: String) -> SimFailure {
        SimFailure(message: message)
    }

    func checkSettled() async throws {
        try checkAlways()
        try checkServerTotals()
        try await checkReactions()
        for phone in phones {
            try await checkLedger(phone)
        }
        for phone in phones {
            guard let viewModel = phone.activeViewModel else { continue }
            try await checkScreen(phone, viewModel)
            try checkUnsentDrawingWentOut(phone)
        }
        try checkProgress()
    }

    private func checkServerTotals() throws {
        guard let game = server.game else { return }
        for round in server.rounds where round.state == .solved {
            if let promised = promisedBonus[round.id], round.speedBonus != promised {
                throw fail("round \(round.id.uuidString.prefix(6)) has speed bonus \(round.speedBonus), the screen promised \(promised)")
            }
            if let promised = promisedHints[round.id], round.hintsUsed != promised {
                throw fail("round \(round.id.uuidString.prefix(6)) has \(round.hintsUsed) hints, the screen showed \(promised)")
            }
            // Any hint takes both bonuses away. The first try is the round's first attempt.
            if round.hintsUsed > 0, round.speedBonus != 0 || round.firstTryBonus != 0 {
                throw fail("round \(round.id.uuidString.prefix(6)) has bonuses after \(round.hintsUsed) hints")
            }
            let expectedFirstTry = round.hintsUsed == 0 && round.attempts.count == 1 ? 1 : 0
            if round.firstTryBonus != expectedFirstTry {
                throw fail("round \(round.id.uuidString.prefix(6)) has first try bonus \(round.firstTryBonus), expected \(expectedFirstTry)")
            }
        }
        let solved = server.rounds.filter { $0.state == .solved }
        let shared = solved.reduce(0) { $0 + $1.points }
        guard game.shared == shared else { throw fail("server shared points \(game.shared) != \(shared)") }
        for user in server.users {
            let expected = solved.reduce(0) { total, round in
                total + (round.drawer == user ? round.points : 0) + (round.guesser == user ? round.points + round.speedBonus + round.firstTryBonus : 0)
            }
            guard (game.points[user] ?? 0) == expected else {
                throw fail("server points for a player \(game.points[user] ?? 0) != \(expected)")
            }
        }
    }

    /// Once the queues drained, the server holds a reaction the guesser's screen showed, unless a
    /// reaction of that round was dropped for good or a phone could not send yet.
    private func checkReactions() async throws {
        var skipped = Set<UUID>()
        for phone in phones {
            let sends = phone.isAlive && phone.isForeground
            for entry in await phone.pending.ledger where entry.kind == .setGameRoundReaction {
                guard let payload = entry.requestData.flatMap({ try? JSONDecoder().decode(GameReactionPayload.self, from: $0) })
                else { continue }
                if case .terminal = entry.outcome {
                    skipped.insert(payload.roundID)
                } else if entry.outcome == .inFlight, !sends {
                    skipped.insert(payload.roundID)
                }
            }
        }
        for (roundID, shown) in shownReactions where !skipped.contains(roundID) {
            let stored = server.round(roundID)?.reaction?.rawValue ?? "none"
            if !shown.contains(stored) {
                throw fail("round \(roundID.uuidString.prefix(6)) has reaction \(stored), the guesser's screen showed \(shown)")
            }
        }
    }

    /// Every write the phone queued either landed once, still waits for a
    /// reason, or was dropped with a notice.
    private func checkLedger(_ phone: SimPhone) async throws {
        let ledger = await phone.pending.ledger
        let decoder = JSONDecoder()
        let storedNotices = await phone.cache.document(ownerUserID: phone.userID).notices.map(GamesNotice.init)
        let notices = phone.notices + storedNotices
        func noticed(_ kinds: [GamesNotice]) -> Bool {
            notices.contains { kinds.contains($0) }
        }
        // A notice about a dropped move needs a dropped move behind it.
        let dropped = Set(ledger.compactMap { entry -> SyncPendingOperationKind? in
            if case .terminal = entry.outcome { entry.kind } else { nil }
        })
        let explains: [GamesNotice: [SyncPendingOperationKind]] = [
            .moveRejected: [.submitGameGuess, .giveUpGameRound],
            .wordRejected: [.pickDrawWord],
            .wordRejectedDrawingKept: [.pickDrawWord],
            .drawingRejected: [.submitGameDrawing],
        ]
        for notice in Set(notices) {
            if let kinds = explains[notice], dropped.isDisjoint(with: kinds) {
                throw fail("\(phone.name) showed \(notice) with no dropped move behind it")
            }
        }
        var guessesByRound: [UUID: (landed: [String], waiting: [String])] = [:]
        for entry in ledger {
            guard let data = entry.requestData else { continue }
            switch entry.kind {
            case .pickDrawWord:
                guard let pick = try? decoder.decode(GamePickWordPayload.self, from: data) else { continue }
                switch entry.outcome {
                case .succeeded:
                    guard server.round(pick.roundID)?.drawer == phone.userID else {
                        throw fail("\(phone.name) pick for \(pick.roundID.uuidString.prefix(6)) succeeded but the server has no such round")
                    }
                case .terminal:
                    guard noticed([.wordRejected, .wordRejectedDrawingKept]) else {
                        throw fail("\(phone.name) pick dropped without a notice")
                    }
                case .inFlight:
                    break
                }
            case .submitGameDrawing:
                guard let drawing = try? decoder.decode(GameSubmitDrawingPayload.self, from: data) else { continue }
                switch entry.outcome {
                case .succeeded:
                    guard let round = server.round(drawing.roundID), let assetID = round.drawingAssetID else {
                        throw fail("\(phone.name) drawing for \(drawing.roundID.uuidString.prefix(6)) succeeded but the round has none")
                    }
                    if server.assets[assetID]?.data != drawing.drawingData {
                        throw fail("\(phone.name) a second drawing for round \(drawing.roundID.uuidString.prefix(6)) was dropped silently")
                    }
                case let .terminal(reason):
                    let explained = reason.contains("upload expired") || reason.contains("word pick for this drawing")
                    guard explained || noticed([.drawingRejected]) else {
                        throw fail("\(phone.name) drawing dropped without a notice: \(reason)")
                    }
                case .inFlight:
                    break
                }
            case .submitGameGuess:
                guard let guess = try? decoder.decode(GameGuessPayload.self, from: data) else { continue }
                let text = SimServer.normalizeWordText(guess.guess)
                switch entry.outcome {
                case .succeeded:
                    guessesByRound[guess.roundID, default: ([], [])].landed.append(text)
                case let .terminal(reason):
                    guard !reason.contains("already finished") else {
                        throw fail("\(phone.name) guess \(text) refused silently: \(reason)")
                    }
                    guard noticed([.moveRejected]) else {
                        throw fail("\(phone.name) guess dropped without a notice: \(reason)")
                    }
                case .inFlight:
                    guessesByRound[guess.roundID, default: ([], [])].waiting.append(text)
                }
            case .giveUpGameRound:
                guard let giveUp = try? decoder.decode(GameGiveUpPayload.self, from: data) else { continue }
                switch entry.outcome {
                case .succeeded:
                    guard server.round(giveUp.roundID)?.state.isFinished == true else {
                        throw fail("\(phone.name) give up succeeded but the round is open")
                    }
                case let .terminal(reason):
                    guard !reason.contains("already finished") else {
                        throw fail("\(phone.name) give up refused silently: \(reason)")
                    }
                    guard noticed([.moveRejected]) else {
                        throw fail("\(phone.name) give up dropped without a notice: \(reason)")
                    }
                case .inFlight:
                    break
                }
            case .markGameRoundResultSeen:
                guard let seen = try? decoder.decode(GameResultSeenPayload.self, from: data) else { continue }
                if case .succeeded = entry.outcome, let round = server.round(seen.roundID) {
                    let stamp = round.drawer == phone.userID ? round.drawerSeenAt : round.guesserSeenAt
                    guard stamp != nil else {
                        throw fail("\(phone.name) result seen succeeded but the server has no time for it")
                    }
                }
            default:
                break
            }
        }
        // No guess is lost or doubled: the server holds each landed guess once,
        // plus at most the ones still waiting that already reached it.
        for (roundID, guesses) in guessesByRound {
            let onServer = (server.round(roundID)?.attempts ?? []).filter { $0.userID == phone.userID }.map(\.text)
            for text in Set(guesses.landed + onServer) {
                let landed = guesses.landed.filter { $0 == text }.count
                let waiting = guesses.waiting.filter { $0 == text }.count
                let held = onServer.filter { $0 == text }.count
                guard held >= landed, held <= landed + waiting else {
                    throw fail("\(phone.name) guess \(text) is on the server \(held) times, sent \(landed), waiting \(waiting)")
                }
            }
        }
        // Once online with nothing held, nothing may stay in the queue.
        guard phone.isAlive, phone.isForeground else { return }
        for entry in ledger where entry.outcome == .inFlight {
            throw fail("\(phone.name) \(entry.kind.rawValue) is stuck in the queue after settling")
        }
    }

    private func checkScreen(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) async throws {
        let name = phone.name
        guard let game = server.game else { return }
        let document = await phone.cache.document(ownerUserID: phone.userID)
        let view = server.view(for: phone.userID)
        guard document.state?.game?.version == game.version else {
            throw fail("\(name) cache has game version \(document.state?.game?.version ?? -1), server \(game.version)")
        }
        let work = await DrawAndGuessPendingWork.load(from: phone.pending, ownerUserID: phone.userID) ?? .none
        if viewModel.phase == .waitingToSync, !work.hasMoveWaiting {
            throw fail("\(name) shows waitingToSync with nothing waiting")
        }
        // Score.
        if let settings = view.settings, let remoteGame = view.game,
           viewModel.score != DrawAndGuessScore(game: remoteGame, playStyle: settings.playStyle) {
            throw fail("\(name) score \(String(describing: viewModel.score)) != server")
        }
        guard !work.hasMoveWaiting else { return }

        // Whose turn, and the phase.
        let current = server.currentRound
        let latestFinished = server.rounds.filter(\.state.isFinished).max { $0.number < $1.number }
        let me = phone.userID
        let expected: Set<DrawAndGuessPhase>
        // A result counts as seen once the server has this person's time for it, or a mark waits on the phone.
        let seenByMe = latestFinished.map { round in
            (round.drawer == phone.userID ? round.drawerSeenAt : round.guesserSeenAt) != nil
                || work.hasResultSeen(roundID: round.id)
        } ?? true
        if let latestFinished, !seenByMe {
            expected = [.reveal]
            if viewModel.round?.id != latestFinished.id {
                throw fail("\(name) reveal should show round \(latestFinished.id.uuidString.prefix(6)), shows \(viewModel.round?.id.uuidString.prefix(6) ?? "none") in \(viewModel.phase)")
            }
        } else {
            switch game.state {
            case .choosingWord:
                expected = game.turnUser == me ? [.chooseWord] : [.waitingForWord]
            case .drawing:
                expected = current?.drawer == me ? [.drawing] : [.waitingForDrawing, .watchingLive]
            case .guessing:
                expected = current?.drawer == me ? [.waitingForGuess] : [.guessing]
            }
        }
        guard expected.contains(viewModel.phase) else {
            throw fail("\(name) phase \(viewModel.phase), expected \(expected) (game \(game.state), turn \(game.turnUser == me ? "me" : "partner"))")
        }

        // The guesser watches live exactly when the drawer is drawing in the room.
        if viewModel.phase == .waitingForDrawing || viewModel.phase == .watchingLive {
            let drawer = partner(of: phone)
            let drawerIsLive = drawer.activeViewModel?.phase == .drawing
                && drawer.socket?.isConnected == true && phone.socket?.isConnected == true
            let expectedPhase: DrawAndGuessPhase = drawerIsLive ? .watchingLive : .waitingForDrawing
            if viewModel.phase != expectedPhase {
                throw fail("\(name) is in \(viewModel.phase), expected \(expectedPhase)")
            }
        }
        // The invite shows only while the partner is away, and waits 15 minutes after one went out.
        let expectedInvite = GameInviteState.make(
            lastInviteAt: view.lastInviteAt,
            partnerIsHere: viewModel.partnerPresence.isHere,
            now: viewModel.now
        )
        if case .sent = viewModel.invite, case .sent = expectedInvite {
            // The phone may know of a send the server has not echoed yet.
        } else if viewModel.invite != expectedInvite {
            throw fail("\(name) invite is \(viewModel.invite), expected \(expectedInvite)")
        }
        // The hub tells the same story. On a reveal it shows the turn that follows it.
        if let summary = phone.games?.drawAndGuess.summary {
            let expectedStatus: DrawAndGuessHubSummary.Status = switch game.state {
            case .choosingWord: game.turnUser == me ? .yourTurnToDraw : .waitingForPartner
            case .drawing: current?.drawer == me ? .yourTurnToDraw : .partnerIsDrawing
            case .guessing: current?.drawer == me ? .waitingForPartner : .yourTurnToGuess
            }
            if summary.status != expectedStatus {
                throw fail("\(name) hub says \(summary.status), expected \(expectedStatus)")
            }
        }

        // A letter a hint showed stays shown, also after a relaunch.
        if viewModel.phase.allowsGuessing, let round = viewModel.round, viewModel.tilesRoundID == round.id,
           viewModel.slots.hintedIndexes != hinted["\(name)-\(round.id)"] ?? [] {
            throw fail("\(name) shows hints at \(viewModel.slots.hintedIndexes), the person saw \(hinted["\(name)-\(round.id)"] ?? [])")
        }

        switch viewModel.phase {
        case .chooseWord:
            if viewModel.choices.count != 3 {
                throw fail("\(name) choose word without three words")
            }
        case .guessing:
            try checkGuesserSeesDrawing(phone, viewModel)
            if viewModel.tiles.isEmpty || viewModel.slots.status == .correct {
                throw fail("\(name) guessing with no tiles or a locked answer")
            }
        case .drawing:
            try checkPartnerLine(phone, viewModel)
        case .watchingLive:
            try checkLiveCanvas(phone, viewModel)
        case .waitingForGuess:
            try checkSentStatus(phone, viewModel)
        case .reveal:
            try checkRevealDrawing(phone, viewModel)
        default:
            break
        }
    }

    /// The round ended while the drawer still had strokes on the canvas or in
    /// the draft. Once the drawer is back in the game, that drawing is the one
    /// the round keeps.
    private func checkUnsentDrawingWentOut(_ phone: SimPhone) throws {
        guard let record = boardStrokes[phone.name], record.count > 0,
              let round = server.round(record.roundID), round.state.isFinished
        else { return }
        guard let assetID = round.drawingAssetID else {
            throw fail("\(phone.name) drew \(record.count) strokes for the ended round \(record.roundID.uuidString.prefix(6)) and never sent them")
        }
        if let data = server.assets[assetID]?.data, let drawing = try? PKDrawing(data: data),
           drawing.strokes.count != record.count {
            throw fail("\(phone.name) sent \(drawing.strokes.count) strokes for \(record.roundID.uuidString.prefix(6)), drew \(record.count)")
        }
    }

    private func checkGuesserSeesDrawing(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) throws {
        if viewModel.guessSource == .live, viewModel.live?.partnerCanvasDrawing?.strokes.isEmpty == false {
            return
        }
        guard viewModel.isReplayReady, let drawing = viewModel.downloadedDrawing, !drawing.strokes.isEmpty else {
            throw fail("\(phone.name) guesser sees a blank canvas (source \(viewModel.guessSource), replay \(viewModel.isReplayReady), loading \(viewModel.isLoadingDrawing), failed \(viewModel.drawingLoadFailed))")
        }
        if let assetID = viewModel.round?.drawingMediaAssetID, let data = server.assets[assetID]?.data,
           let serverDrawing = try? PKDrawing(data: data), serverDrawing.strokes.count != drawing.strokes.count {
            throw fail("\(phone.name) replay has \(drawing.strokes.count) strokes, the sent drawing \(serverDrawing.strokes.count)")
        }
    }

    /// A guesser watching live sees every stroke the drawer has on the canvas.
    private func checkLiveCanvas(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) throws {
        let drawer = partner(of: phone)
        guard let drawerModel = drawer.activeViewModel, drawerModel.phase == .drawing, drawer.canvas != nil,
              drawer.socket?.isConnected == true, phone.socket?.isConnected == true
        else { return }
        let drawn = drawerModel.board.drawing.strokes.count
        let shown = viewModel.live?.partnerCanvasDrawing?.strokes.count ?? 0
        guard drawn == shown else {
            throw fail("\(phone.name) watches \(shown) live strokes, the drawer has \(drawn)")
        }
    }

    /// What the partner's phone is really doing, as this phone should show it.
    private func expectedPresence(of partner: SimPhone, seenFrom phone: SimPhone) -> DrawAndGuessPartnerPresence {
        if let partnerModel = partner.activeViewModel, partner.socket?.isConnected == true, phone.socket?.isConnected == true {
            let isDrawer = partnerModel.round.map { $0.isDrawer(partner.userID) && !$0.isFinished } ?? false
            switch DrawAndGuessPhase.liveRole(phase: partnerModel.phase, isDrawerOfUnfinishedRound: isDrawer) {
            case .drawing: return .drawing
            case .watching: return .watching
            case .choosing: return .choosing
            case .result: return .result
            case .present: return .here
            }
        }
        if let stamp = server.presenceStamp(of: partner.userID), clock.now.timeIntervalSince(stamp) < GamePresence.freshInterval {
            return .here
        }
        return .away
    }

    func partner(of phone: SimPhone) -> SimPhone {
        phone === phones[0] ? phones[1] : phones[0]
    }

    private func checkPartnerLine(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) throws {
        let expected = expectedPresence(of: partner(of: phone), seenFrom: phone)
        guard viewModel.partnerPresence == expected else {
            throw fail("\(phone.name) drawer shows partner \(viewModel.partnerPresence), partner is \(expected)")
        }
    }

    private func checkSentStatus(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) throws {
        try checkPartnerLine(phone, viewModel)
        guard !viewModel.isWaitingToSend, let round = viewModel.round else { return }
        let expected = DrawAndGuessSentStatus.make(
            partner: expectedPresence(of: partner(of: phone), seenFrom: phone),
            guesserFirstSeenAt: server.round(round.id)?.firstSeenAt
        )
        guard viewModel.sentStatus == expected else {
            throw fail("\(phone.name) sent status \(viewModel.sentStatus), expected \(expected)")
        }
    }

    /// A revealed round whose drawing exists has something to show on both phones.
    private func checkRevealDrawing(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) throws {
        guard let round = viewModel.round, server.round(round.id)?.drawingAssetID != nil else { return }
        guard let final = viewModel.finalDrawing, !final.drawing.strokes.isEmpty else {
            throw fail("\(phone.name) reveal of \(round.id.uuidString.prefix(6)) has no drawing to show (loading \(viewModel.isLoadingDrawing), failed \(viewModel.drawingLoadFailed))")
        }
    }

    /// The game moves on while the person whose turn it is has the game open.
    private func checkProgress() throws {
        guard let game = server.game else { return }
        if game.version != lastProgressVersion {
            lastProgressVersion = game.version
            settlesWithoutProgress = 0
            return
        }
        let actor = phones.first { $0.userID == game.turnUser }
        if actor?.activeViewModel != nil {
            settlesWithoutProgress += 1
        }
        if settlesWithoutProgress > 30 {
            throw fail("no progress for 30 settles with the turn's player in the game")
        }
    }
}
