import Foundation
import PencilKit
@testable import PaeoniaApp

// What each open game screen shows once the network is up and the queues have drained.
extension SimDriver {
    func checkScreen(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) async throws {
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

        try checkPhase(phone, viewModel, game: game, work: work)
        try checkWatchingLive(phone, viewModel)
        try checkInvite(phone, viewModel, view: view)
        try checkHub(phone, game: game)
        // A letter a hint showed stays shown, also after a relaunch.
        if viewModel.phase.allowsGuessing, let round = viewModel.round, viewModel.tilesRoundID == round.id,
           viewModel.slots.hintedIndexes != hinted["\(name)-\(round.id)"] ?? [] {
            throw fail(
                "\(name) shows hints at \(viewModel.slots.hintedIndexes), "
                    + "the person saw \(hinted["\(name)-\(round.id)"] ?? [])"
            )
        }
        try checkPhaseDetails(phone, viewModel)
    }

    /// Whose turn it is, and so which phase the screen is in.
    private func checkPhase(
        _ phone: SimPhone,
        _ viewModel: DrawAndGuessViewModel,
        game: SimServer.Game,
        work: DrawAndGuessPendingWork
    ) throws {
        let name = phone.name
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
                throw fail(
                    "\(name) reveal should show round \(tag(latestFinished.id)), "
                        + "shows \(viewModel.round.map { tag($0.id) } ?? "none") in \(viewModel.phase)"
                )
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
            throw fail(
                "\(name) phase \(viewModel.phase), expected \(expected) "
                    + "(game \(game.state), turn \(game.turnUser == me ? "me" : "partner"))"
            )
        }
    }

    /// The guesser watches live exactly when the drawer is drawing in the room.
    private func checkWatchingLive(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) throws {
        guard viewModel.phase == .waitingForDrawing || viewModel.phase == .watchingLive else { return }
        let drawer = partner(of: phone)
        let drawerIsLive = drawer.activeViewModel?.phase == .drawing
            && drawer.socket?.isConnected == true && phone.socket?.isConnected == true
        let expectedPhase: DrawAndGuessPhase = drawerIsLive ? .watchingLive : .waitingForDrawing
        if viewModel.phase != expectedPhase {
            throw fail("\(phone.name) is in \(viewModel.phase), expected \(expectedPhase)")
        }
    }

    /// The invite shows only while the partner is away, and waits 15 minutes after one went out.
    private func checkInvite(
        _ phone: SimPhone,
        _ viewModel: DrawAndGuessViewModel,
        view: RemoteDrawAndGuessState
    ) throws {
        let expectedInvite = GameInviteState.make(
            lastInviteAt: view.lastInviteAt,
            partnerIsHere: viewModel.partnerPresence.isHere,
            now: viewModel.now
        )
        if case .sent = viewModel.invite, case .sent = expectedInvite {
            // The phone may know of a send the server has not echoed yet.
        } else if viewModel.invite != expectedInvite {
            throw fail("\(phone.name) invite is \(viewModel.invite), expected \(expectedInvite)")
        }
    }

    /// The hub tells the same story. On a reveal it shows the turn that follows it.
    private func checkHub(_ phone: SimPhone, game: SimServer.Game) throws {
        guard let summary = phone.games?.drawAndGuess.summary else { return }
        let me = phone.userID
        let current = server.currentRound
        let expectedStatus: DrawAndGuessHubSummary.Status = switch game.state {
        case .choosingWord: game.turnUser == me ? .yourTurnToDraw : .waitingForPartner
        case .drawing: current?.drawer == me ? .yourTurnToDraw : .partnerIsDrawing
        case .guessing: current?.drawer == me ? .waitingForPartner : .yourTurnToGuess
        }
        if summary.status != expectedStatus {
            throw fail("\(phone.name) hub says \(summary.status), expected \(expectedStatus)")
        }
    }

    private func checkPhaseDetails(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) throws {
        switch viewModel.phase {
        case .chooseWord:
            try checkThreeChoices(phone, viewModel)
        case .guessing:
            try checkGuessingScreen(phone, viewModel)
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

    private func checkThreeChoices(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) throws {
        if viewModel.choices.count != 3 {
            throw fail("\(phone.name) choose word without three words")
        }
    }

    private func checkGuessingScreen(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) throws {
        try checkGuesserSeesDrawing(phone, viewModel)
        if viewModel.tiles.isEmpty || viewModel.slots.status == .correct {
            throw fail("\(phone.name) guessing with no tiles or a locked answer")
        }
    }

    /// The round ended while the drawer still had strokes on the canvas or in
    /// the draft. Once the drawer is back in the game, that drawing is the one
    /// the round keeps.
    func checkUnsentDrawingWentOut(_ phone: SimPhone) throws {
        // `count` is a stroke count, not a collection, so there is no `isEmpty`.
        // swiftlint:disable:next empty_count
        guard let record = boardStrokes[phone.name], record.count > 0,
              let round = server.round(record.roundID), round.state.isFinished
        else { return }
        guard let assetID = round.drawingAssetID else {
            throw fail(
                "\(phone.name) drew \(record.count) strokes for the ended round \(tag(record.roundID)) "
                    + "and never sent them"
            )
        }
        if let data = server.assets[assetID]?.data, let drawing = try? PKDrawing(data: data),
           drawing.strokes.count != record.count {
            throw fail(
                "\(phone.name) sent \(drawing.strokes.count) strokes for \(tag(record.roundID)), "
                    + "drew \(record.count)"
            )
        }
    }

    private func checkGuesserSeesDrawing(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) throws {
        if viewModel.guessSource == .live, viewModel.live?.partnerCanvasDrawing?.strokes.isEmpty == false {
            return
        }
        guard viewModel.isReplayReady, let drawing = viewModel.downloadedDrawing, !drawing.strokes.isEmpty else {
            throw fail(
                "\(phone.name) guesser sees a blank canvas (source \(viewModel.guessSource), "
                    + "replay \(viewModel.isReplayReady), loading \(viewModel.isLoadingDrawing), "
                    + "failed \(viewModel.drawingLoadFailed))"
            )
        }
        if let assetID = viewModel.round?.drawingMediaAssetID, let data = server.assets[assetID]?.data,
           let serverDrawing = try? PKDrawing(data: data), serverDrawing.strokes.count != drawing.strokes.count {
            throw fail(
                "\(phone.name) replay has \(drawing.strokes.count) strokes, "
                    + "the sent drawing \(serverDrawing.strokes.count)"
            )
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
        if let partnerModel = partner.activeViewModel,
           partner.socket?.isConnected == true, phone.socket?.isConnected == true {
            let isDrawer = partnerModel.round.map { $0.isDrawer(partner.userID) && !$0.isFinished } ?? false
            switch DrawAndGuessPhase.liveRole(phase: partnerModel.phase, isDrawerOfUnfinishedRound: isDrawer) {
            case .drawing: return .drawing
            case .watching: return .watching
            case .choosing: return .choosing
            case .result: return .result
            case .present: return .here
            }
        }
        if server.presenceStamp(of: partner.userID) != nil {
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
            throw fail(
                "\(phone.name) reveal of \(tag(round.id)) has no drawing to show "
                    + "(loading \(viewModel.isLoadingDrawing), failed \(viewModel.drawingLoadFailed))"
            )
        }
    }
}
