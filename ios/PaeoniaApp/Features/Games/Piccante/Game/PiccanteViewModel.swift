import Foundation
import Observation

@Observable
final class PiccanteViewModel {
    var state: RemotePiccanteState?
    var game: RemotePiccanteGame?
    var participants = GameParticipants()
    var selected: Int?
    var partnerSelected: Int?
    var note = "" {
        didSet {
            let capped = PiccanteRules.cappedNote(note)
            if note != capped { note = capped }
        }
    }
    var shownBites = 0
    var revealSettled = false
    var noteRevealed = false
    var burnRevealed = false
    var burnShake = 0
    var heldTile: Int?
    var partnerHere = false
    var invite: GameInviteState = .hidden
    var notice: GamesNotice?
    var failure: PaeoniaFailure?
    var isSaving = false
    var isSendFailing = false
    var playStyle = GamePlayStyle.against
    let reactions = GameLiveReactions()
    @ObservationIgnored let dependencies: GamesDependencies
    @ObservationIgnored var sync: (@MainActor @Sendable () async -> Void)?
    @ObservationIgnored var loops: GameScreenLoops
    @ObservationIgnored var running = false
    @ObservationIgnored var active = true
    @ObservationIgnored var replayTask: Task<Void, Never>?
    @ObservationIgnored var live: WidgetLiveDrawing?
    @ObservationIgnored var channel: GameLiveChannel<PiccanteLiveMessage>?
    @ObservationIgnored var liveObservation: Task<Void, Never>?
    @ObservationIgnored var attention = GameAttentionCue()
    @ObservationIgnored var deferredResult: Int?
    @ObservationIgnored var localInviteSentAt: Date?
    @ObservationIgnored var lastHeartbeatLift: Int?
    @ObservationIgnored var lastMove: PiccanteMove?
    @ObservationIgnored var reloadGate = GameReloadGate()
    @ObservationIgnored var playbackClockTask: Task<Void, Never>?
    @ObservationIgnored var playbackClock: PiccantePlaybackClock?
    var reduceMotion = false

    init(dependencies: GamesDependencies) {
        self.dependencies = dependencies
        loops = GameScreenLoops(
            kind: .piccante, gateway: dependencies.gateway,
            heartbeatInterval: GamePresence.heartbeatInterval, sleep: { try await Task.sleep(for: $0) })
    }
    var userID: UUID? { participants.currentUserID }
    var partnerName: String { participants.partnerName }
    var isMyTurn: Bool { game?.turnUserID == userID && userID != nil }
    var canAct: Bool {
        (game?.phase == .choosing || isMyTurn) && !isSaving && heldTile == nil && shownBites == game?.bites.count
    }
    var status: LocalizedStringResource {
        guard let game else { return .piccanteLoading }
        if heldTile != nil { return .piccanteWaitingBite }
        if game.phase == .finished {
            if !revealSettled { return .piccanteOpeningChocolate }
            if Set(game.chilis.map(\.tile)).count == 1 { return .piccanteSameOneHeadline }
            if game.myChili == game.bites.last?.tile && game.loserUserID == userID {
                return .piccanteOwnBurn
            }
            return game.loserUserID == userID ? .piccanteGotYou(partnerName) : .piccanteYouGot(partnerName)
        }
        if game.phase == .choosing { return .piccanteChooseTitle }
        if !isMyTurn {
            return game.phase == .hiding ? .piccanteWaitingHiding(partnerName) : .piccanteWaitingPicking(partnerName)
        }
        switch game.phase {
        case .choosing: return .piccanteChooseTitle
        case .hiding: return .piccanteHideTitle
        case .biting: return .piccanteBiteTitle
        case .finished: return .piccanteFinished
        }
    }
    func configure(participants: GameParticipants) {
        if userID != participants.currentUserID || self.participants.coupleID != participants.coupleID {
            stop(markResultSeen: false)
            live = nil
            channel = nil
            localInviteSentAt = nil
            state = nil
            game = nil
            selected = nil
            partnerSelected = nil
            note = ""
            deferredResult = nil
            lastMove = nil
        }
        self.participants = participants
    }
    func start() async {
        guard !running else { return }
        running = true
        await reload()
        loops.beginObserving(
            currentUserID: { [weak self] in self?.userID }, reload: { [weak self] in await self?.reload() })
        loops.beginTicking(every: .seconds(15)) { [weak self] in Task { await self?.reload() } }
        loops.beginHeartbeat()
        startLive()
        await refresh()
    }
    func stop(markResultSeen: Bool = true) {
        if markResultSeen, noteRevealed, let game, game.phase == .finished, let userID {
            queueSeenOnExit(game, userID: userID)
        }
        running = false
        loops.cancelFollowing()
        loops.endHeartbeat()
        live?.stop()
        liveObservation?.cancel()
        playbackClockTask?.cancel()
        playbackClockTask = nil
        playbackClock = nil
        replayTask?.cancel()
        replayTask = nil
        partnerSelected = nil
        reactions.clear()
        attention.reset()
    }
    func scenePhaseChanged(_ active: Bool) {
        self.active = active
        if active {
            playbackClockTask?.cancel()
            playbackClockTask = nil
            playbackClock = nil
            loops.beginHeartbeat()
            startLive()
            loops.refresh { [weak self] in await self?.refresh() }
        } else {
            loops.endHeartbeat()
            live?.stop()
            partnerSelected = nil
        }
    }
    func refresh() async {
        guard let userID else { return }
        do {
            let loaded =
                state?.game == nil
                ? try await dependencies.piccanteGateway.ensurePiccante()
                : try await dependencies.piccanteGateway.loadPiccante()
            guard self.userID == userID, loaded.coupleID == participants.coupleID else { return }
            await dependencies.piccanteCache.saveState(loaded, ownerUserID: userID)
            failure = nil
            await reload()
        } catch { failure = PaeoniaFailure(error) }
    }
    func reload() async {
        guard let userID else { return }
        if running { startPlaybackClock() }
        let ticket = reloadGate.begin()
        let document = await dependencies.piccanteCache.document(ownerUserID: userID)
        guard self.userID == userID, document.state.map({ $0.coupleID == participants.coupleID }) ?? true else {
            return
        }
        var operationsInFlight: [PendingSyncOperationSnapshot] = []
        var sendFailed = false
        do {
            for kind in PiccanteAction.allCases.map(\.pendingKind) {
                let operations = try await dependencies.pendingOperationStore.inFlightOperations(
                    ownerUserID: userID, kind: kind)
                sendFailed = sendFailed || operations.contains(where: \.failedWhileOnline)
                operationsInFlight += operations
            }
        } catch { return }
        let pending = operationsInFlight.sorted {
            $0.operation.clientSequence < $1.operation.clientSequence
        }.compactMap { $0.requestData.flatMap { try? JSONDecoder().decode(PiccanteMove.self, from: $0) } }
        let overview = await dependencies.cache.document(ownerUserID: userID).overview
        guard self.userID == userID, document.state.map({ $0.coupleID == participants.coupleID }) ?? true,
            reloadGate.apply(ticket)
        else { return }
        isSendFailing = sendFailed
        playStyle = overview?.settings?.playStyle ?? .against
        partnerHere =
            live.map { $0.partnerActivity != .away } == true
            || overview?.presence(for: .piccante)?.partnerPresent == true
        if !partnerHere { partnerSelected = nil }
        if !partnerHere { lastHeartbeatLift = nil }
        invite = GameInviteState.make(
            lastInviteAt: overview?.presence(for: .piccante)?.lastInviteAt,
            localSentAt: localInviteSentAt, partnerIsHere: partnerHere, now: dependencies.now())
        state = document.state
        let resolution = PiccanteResolver.resolve(state: state, pending: pending, deferredResult: deferredResult)
        let next = resolution.game
        heldTile = resolution.heldTile
        let versionChanged = game?.version != next?.version
        if !PiccanteRules.keepsSelection(from: game, to: next) {
            selected = nil
            partnerSelected = nil
            lastHeartbeatLift = nil
        }
        game = next
        if versionChanged { sendSelection() }
        if let game, replayTask == nil, shownBites != game.bites.count || !revealSettled && game.phase == .finished {
            beginReplay(from: document.shown)
        }
        if let game {
            let lastPartner = game.bites.last?.userID != userID && !game.bites.isEmpty
            attention.update(
                GameAttention(
                    turn: isMyTurn
                        && (lastPartner || game.phase == .hiding && game.partnerHidden && game.myChili == nil)
                        ? "\(game.gameNumber):\(game.phase.rawValue):\(game.bites.count)" : nil,
                    partnerStep: game.partnerSniffUsed ? "sniff:\(game.gameNumber)" : nil), isActive: running && active)
        }
        await restoreRefusedMoves(ownerUserID: userID)
    }
    private func restoreRefusedMoves(ownerUserID: UUID) async {
        let refused = await dependencies.piccanteCache.takeRefused(ownerUserID: ownerUserID)
        guard userID == ownerUserID else { return }
        if !refused.isEmpty {
            notice = .moveRejected
            if let hide = refused.last(where: {
                $0.action == .hide && $0.gameID == game?.id && $0.gameNumber == game?.gameNumber
            }), game?.phase == .hiding, game?.myChili == nil, isMyTurn {
                note = hide.note ?? ""
                selected = hide.tile
            }
        }
    }
    func select(_ tile: Int) {
        guard let game, canAct, !game.bites.contains(where: { $0.tile == tile }) else { return }
        selected = tile
        PaeoniaHaptics.selection()
        GameSound.piccanteLift.play()
        sendSelection()
    }
}
