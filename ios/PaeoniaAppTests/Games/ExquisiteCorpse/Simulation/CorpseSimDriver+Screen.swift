import Foundation
import PencilKit
@testable import PaeoniaApp

// What each phone's screen shows, against the server's state.
extension CorpseSimDriver {
    func checkScreen(_ phone: CorpseSimPhone, _ viewModel: ExquisiteCorpseViewModel) async throws {
        guard let game = server.game else { return }
        let document = await phone.corpseCache.document(ownerUserID: phone.userID)
        guard document.state?.game?.version == game.version else {
            let cached = document.state?.game?.version ?? -1
            throw fail("\(phone.name) cache has game version \(cached), server \(game.version)")
        }
        let work = await ExquisiteCorpsePendingWork.load(from: phone.pending, ownerUserID: phone.userID) ?? .none
        if viewModel.phase == .waitingToSync, !work.hasMoveWaiting {
            throw fail("\(phone.name) shows waitingToSync with nothing waiting")
        }
        guard !work.hasMoveWaiting else { return }
        try checkPhase(phone, viewModel, game: game, work: work)
        try checkInvite(phone, viewModel)
        try checkPresence(phone, viewModel)
        switch viewModel.phase {
        case .drawing: try checkStripAbove(phone, viewModel)
        case .watching: try checkWatching(phone, viewModel)
        case .reveal: try checkReveal(phone, viewModel)
        default: break
        }
    }

    /// The phase is what the resolver makes of the server's state, and the unseen reveal comes before a new turn.
    private func checkPhase(
        _ phone: CorpseSimPhone,
        _ viewModel: ExquisiteCorpseViewModel,
        game: CorpseSimServer.Game,
        work: ExquisiteCorpsePendingWork
    ) throws {
        let isLive = isPartnerLive(for: phone)
        let resolution = ExquisiteCorpseResolver(userID: phone.userID).resolve(
            state: server.state(for: phone.userID),
            hasSettings: true,
            pending: work,
            isPartnerDrawingLive: isLive
        )
        guard allowedPhases(for: phone, resolution.phase, isLive: isLive).contains(viewModel.phase) else {
            throw fail("\(phone.name) phase \(viewModel.phase), the server's state says \(resolution.phase)")
        }
        let latest = server.figures.filter { $0.finishedAt != nil }.max { $0.number < $1.number }
        let hasSeen = latest.map { $0.seenAt[phone.userID] != nil || work.hasRevealSeen(figureID: $0.id) } ?? true
        if let latest, !hasSeen {
            guard viewModel.phase == .reveal, viewModel.figure?.id == latest.id else {
                throw fail("\(phone.name) should show the reveal of figure \(latest.number), shows \(viewModel.phase)")
            }
        } else if viewModel.phase == .reveal {
            throw fail("\(phone.name) shows a reveal that was already seen")
        } else if (game.turnUser == phone.userID) != (viewModel.phase == .drawing) {
            let whose = game.turnUser == phone.userID ? "own" : "partner's"
            throw fail("\(phone.name) is in \(viewModel.phase) on the \(whose) turn")
        }
    }

    /// Waiting and watching differ only by what the room says, which a dropped socket or a partner
    /// who is handing a part over can blur.
    private func allowedPhases(
        for phone: CorpseSimPhone,
        _ phase: ExquisiteCorpsePhase,
        isLive: Bool
    ) -> Set<ExquisiteCorpsePhase> {
        guard phase == .waiting || phase == .watching, !isLive else { return [phase] }
        let other = partner(of: phone)
        let otherWorking = other.activeViewModel.map { $0.phase == .drawing || $0.isWaitingToSend } ?? false
        let isInTheRoom = phone.socket?.isConnected == true && other.socket?.isConnected == true
        return !otherWorking && isInTheRoom && other.activeViewModel != nil ? [.waiting] : [.waiting, .watching]
    }

    /// With both phones in the room, each sees the other there.
    private func checkPresence(_ phone: CorpseSimPhone, _ viewModel: ExquisiteCorpseViewModel) throws {
        let other = partner(of: phone)
        let isInTheRoom = other.activeViewModel != nil && phone.socket?.isConnected == true
            && other.socket?.isConnected == true
        if [.drawing, .watching, .waiting].contains(viewModel.phase), isInTheRoom, !viewModel.partnerPresence.isInRoom {
            throw fail("\(phone.name) does not see the partner in the room (shows \(viewModel.partnerPresence))")
        }
    }

    private func checkInvite(_ phone: CorpseSimPhone, _ viewModel: ExquisiteCorpseViewModel) throws {
        let expected = GameInviteState.make(
            lastInviteAt: server.overview(for: phone.userID).presence(for: .exquisiteCorpse)?.lastInviteAt,
            partnerIsHere: viewModel.partnerPresence.isHere,
            now: viewModel.now
        )
        if case .sent = viewModel.invite, case .sent = expected {
            // The phone may know of a send the server has not echoed yet.
            return
        }
        guard viewModel.invite == expected else {
            throw fail("\(phone.name) invite is \(viewModel.invite), expected \(expected)")
        }
    }

    /// The partner is drawing in the room, with both sockets up, as this phone should see it.
    private func isPartnerLive(for phone: CorpseSimPhone) -> Bool {
        let other = partner(of: phone)
        guard let model = other.activeViewModel, phone.socket?.isConnected == true, other.socket?.isConnected == true
        else { return false }
        let isHandingOff = model.isWaitingToSend && [.waiting, .watching, .waitingToSync].contains(model.phase)
        return model.phase == .drawing || isHandingOff
    }

    /// The strip above a drawer's canvas is the bottom of the part before.
    private func checkStripAbove(_ phone: CorpseSimPhone, _ viewModel: ExquisiteCorpseViewModel) throws {
        guard let part = viewModel.part, let previous = part.previous, !viewModel.isLoadingStrip else { return }
        let before = server.parts.last { $0.index == previous.rawValue }
        guard let full = drawing(of: before?.drawingAssetID) else { return }
        let expected = ExquisiteCorpseFold.strip(of: full)
        guard viewModel.strip?.paeoniaContentSignature == expected.paeoniaContentSignature else {
            let shown = viewModel.strip?.strokes.count ?? -1
            let want = expected.strokes.count
            throw fail("\(phone.name) shows \(shown) strokes of strip above the \(part), expected \(want)")
        }
    }

    /// A watcher sees the strokes that reach the strip.
    private func checkWatching(_ phone: CorpseSimPhone, _ viewModel: ExquisiteCorpseViewModel) throws {
        guard let drawer = partner(of: phone).activeViewModel, drawer.phase == .drawing,
              drawer.part?.hasStrip == true, drawer.live?.partnerActivity == .watching
        else { return }
        let expected = ExquisiteCorpseFold.strip(of: drawer.board.canonicalDrawing)
        let shown = viewModel.partnerStrip ?? PKDrawing()
        guard shown.paeoniaContentSignature == expected.paeoniaContentSignature else {
            let want = expected.strokes.count
            throw fail("\(phone.name) watches \(shown.strokes.count) strokes, the drawer's strip has \(want)")
        }
    }

    /// A reveal shows the three parts as the server holds them.
    private func checkReveal(_ phone: CorpseSimPhone, _ viewModel: ExquisiteCorpseViewModel) throws {
        guard let figure = viewModel.figure, let content = viewModel.revealContent, content.figureID == figure.id,
              content.isReady
        else {
            let state = "loading \(viewModel.isLoadingReveal), failed \(viewModel.revealLoadFailed)"
            throw fail("\(phone.name) reveal is not ready (\(state))")
        }
        for shown in content.parts {
            let part = server.parts.first { $0.figureID == figure.id && $0.index == shown.kind.rawValue }
            let expected = drawing(of: part?.drawingAssetID)
            guard shown.drawing?.paeoniaContentSignature == expected?.paeoniaContentSignature else {
                throw fail("\(phone.name) reveal shows another \(shown.kind) than the server holds")
            }
            guard shown.idea == part?.idea?.text else {
                throw fail("\(phone.name) reveal shows the wrong idea for the \(shown.kind)")
            }
        }
    }
}
