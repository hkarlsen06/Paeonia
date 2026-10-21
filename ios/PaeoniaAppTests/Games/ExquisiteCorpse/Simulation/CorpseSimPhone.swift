import Foundation
import PencilKit
@testable import PaeoniaApp

/// One phone: its own Games overview cache, corpse cache, pending operations,
/// drawings on disk and relay socket, and a real `ExquisiteCorpseViewModel` wired
/// as `GamesDependencies.live()` and the sync service wire it. It runs the real
/// drain with the two corpse handlers, and stands in for the live feed.
///
/// The stores outlive a force quit. The view model, the tasks and the socket do not.
@MainActor
final class CorpseSimPhone {
    static let queuedKinds: [SyncPendingOperationKind] = [
        .exquisiteCorpseSubmitPart, .exquisiteCorpseRevealSeen,
    ]

    let name: String
    let userID: UUID
    let partnerID: UUID
    let server: CorpseSimServer
    let relay: SimRelay
    let clock: SimClock
    let log: SimLog
    let network: SimNetwork
    let canvasSide: CGFloat

    // What a force quit keeps.
    let overviewCache: InMemoryGamesCache
    let corpseCache = InMemoryExquisiteCorpseCache()
    let pending = SimPendingStore(gameKinds: CorpseSimPhone.queuedKinds)
    let drawingStore = InMemoryGameDrawingStore()
    let operations: SimOperationProvider
    /// What the view model reads as its steady clock. The driver moves it as a pen moves.
    let penClock = CorpseClock()

    // One app launch.
    private(set) var viewModel: ExquisiteCorpseViewModel?
    private(set) var socket: SimRelaySocket?
    var gateway: CorpseSimGateway?
    var drain: PendingSyncOperationDrainStream?
    var startTask: Task<Void, Never>?

    private(set) var isAlive = false
    var isScreenOpen = false
    var isForeground = true

    // The live feed stand-in.
    var isFeedOutage = false
    /// Delivers states one at a time and late, so an older state can land after a newer read.
    var isFeedDelayed = false
    var feedQueue: [(RemoteExquisiteCorpseState, RemoteGamesOverview)] = []
    var feedCapturedVersion = -1
    var feedWasUp = false

    // The sync.
    var syncTask: Task<Void, Never>?
    var syncFollowUp = false

    /// Notices the screen showed, in order.
    var notices: [GamesNotice] = []
    var launchCount = 0

    // What left this phone over the relay, for the privacy checks.
    var stripsSent = 0
    var leaks: [String] = []

    init(
        name: String,
        userID: UUID,
        partnerID: UUID,
        server: CorpseSimServer,
        relay: SimRelay,
        clock: SimClock,
        log: SimLog,
        random: SimRandom,
        canvasSide: CGFloat
    ) {
        self.name = name
        self.userID = userID
        self.partnerID = partnerID
        self.server = server
        self.relay = relay
        self.clock = clock
        self.log = log
        self.canvasSide = canvasSide
        network = SimNetwork(name: name, log: log, random: random)
        operations = SimOperationProvider(clock: clock)
        overviewCache = InMemoryGamesCache(overview: server.overview(for: userID), ownerUserID: userID)
        let reporter = CorpseEnqueueReporter(phone: self)
        let pending = pending
        Task {
            await pending.setOnEnqueue { kind, _ in
                Task { @MainActor in reporter.report(kind) }
            }
        }
    }

    var participants: GameParticipants {
        GameParticipants(
            currentUserID: userID,
            coupleID: server.coupleID,
            partnerName: name == "A" ? "Robin" : "Alex",
            currentName: name == "A" ? "Alex" : "Robin"
        )
    }

    /// The view model while the game screen is open and the app is in front.
    var activeViewModel: ExquisiteCorpseViewModel? {
        isAlive && isScreenOpen && isForeground ? viewModel : nil
    }

    // MARK: - Launch and force quit

    func launch() {
        guard !isAlive else { return }
        isAlive = true
        isForeground = true
        isScreenOpen = false
        launchCount += 1
        let gateway = CorpseSimGateway(user: userID, server: server, network: network)
        let transfer = CorpseSimTransfer(user: userID, server: server, network: network)
        self.gateway = gateway
        drain = makeDrain(gateway: gateway, transfer: transfer)
        let clock = clock
        let dependencies = GamesDependencies(
            gateway: gateway,
            cache: overviewCache,
            pendingOperationStore: pending,
            operationProvider: operations,
            drawingStore: drawingStore,
            drawingTransfer: transfer,
            makeLive: { _ in nil },
            now: { clock.now },
            exquisiteCorpseGateway: gateway,
            exquisiteCorpseCache: corpseCache,
            makeExquisiteCorpseLive: { [weak self] _ in self?.makeLiveRoom() }
        )
        // The heartbeat and the tick run as the driver moves the clock, so their own timers never fire.
        let penClock = penClock
        let viewModel = ExquisiteCorpseViewModel(
            dependencies: dependencies,
            participants: participants,
            heartbeatInterval: .seconds(36_000),
            tickInterval: .seconds(36_000),
            monotonicNow: { penClock.now },
            sleep: { try await Task.sleep(for: $0 / 1_000) }
        )
        viewModel.setLocalChangeSyncHandler { [weak self] in await self?.sync() }
        self.viewModel = viewModel
        feedWasUp = false
        log.add("\(name) launch #\(launchCount)")
        // The sync service runs once at launch.
        Task { await self.sync() }
    }

    private func makeDrain(gateway: CorpseSimGateway, transfer: CorpseSimTransfer) -> PendingSyncOperationDrainStream {
        PendingSyncOperationDrainStream(handlers: [
            ExquisiteCorpseSubmitPartHandler(
                gateway: gateway,
                transfer: transfer,
                cache: corpseCache,
                drawingStore: drawingStore
            ),
            ExquisiteCorpseRevealSeenHandler(gateway: gateway, cache: corpseCache),
        ], retryPolicy: PendingSyncOperationRetryPolicy(baseDelaySeconds: 0))
    }

    private func makeLiveRoom() -> WidgetLiveDrawing {
        let gateway = gateway
        let socket = SimRelaySocket(
            relay: relay,
            user: userID,
            phoneName: name,
            isOnline: { [weak self] in
                guard let self else { return false }
                return isAlive && network.isOnline
            },
            fetchTicket: { try await gateway?.fetchLiveTicket() }
        )
        socket.onSendGameData = { [weak self] data in self?.inspect(gameData: data) }
        socket.onSendMessage = { [weak self] message in self?.inspect(message) }
        self.socket = socket
        return WidgetLiveDrawing(
            connection: socket,
            role: .present,
            presence: WidgetLivePresence(countsLatestHelloOnly: true)
        )
    }

    /// The system kills the app. Nothing runs after this, and nothing is saved
    /// that was not saved already. `closesSocket` decides whether the relay hears it go.
    func forceQuit(closesSocket: Bool) {
        guard isAlive else { return }
        log.add("\(name) force quit (socket \(closesSocket ? "closed" : "silent"))")
        isAlive = false
        network.killApp()
        // A request on its way may or may not have reached the server.
        network.releaseHeld()
        syncTask?.cancel()
        syncTask = nil
        syncFollowUp = false
        startTask?.cancel()
        startTask = nil
        if let viewModel {
            viewModel.cancelTasks()
            viewModel.loops.cancelHeartbeat()
            viewModel.liveObservationTask?.cancel()
            viewModel.liveObservationTask = nil
            viewModel.isRunning = false
            viewModel.isStopped = true
        }
        if let socket {
            if !closesSocket {
                socket.dropSilently()
            }
            socket.stop()
        }
        socket = nil
        viewModel = nil
        gateway = nil
        drain = nil
        isScreenOpen = false
    }

    func shutDown() {
        if isScreenOpen {
            viewModel?.stop()
        }
        forceQuit(closesSocket: true)
        network.releaseHeld(deliverAll: true)
    }

    /// The phone's view of the world, for spotting when it stopped changing.
    func fingerprint() async -> String {
        let queue = await pending.fingerprint(ownerUserID: userID)
        let document = await corpseCache.document(ownerUserID: userID)
        var parts = [queue, "\(document.state?.game?.version ?? -1)", "\(document.notices.count)"]
        if let viewModel {
            parts += [
                "\(viewModel.phase)",
                "\(viewModel.figure?.id.uuidString.prefix(6) ?? "-")",
                "\(viewModel.figure?.parts.count ?? -1)",
                "\(viewModel.isLoadingStrip)",
                "\(viewModel.strip?.paeoniaContentSignature ?? 0)",
                "\(viewModel.partnerStrip?.paeoniaContentSignature ?? 0)",
                "\(viewModel.partnerDonePulse)",
                "\(viewModel.revealContent?.isReady ?? false)",
                "\(viewModel.isLoadingReveal)",
                "\(viewModel.partnerPresence)",
                "\(viewModel.idea?.id ?? "-")",
                "\(viewModel.live?.partnerActivity ?? .away)",
                "\(viewModel.live?.roomVersion ?? -1)",
            ]
        }
        parts.append("\(network.inFlight - network.heldCount)")
        parts.append("\(isSyncing)")
        parts.append("\(socket?.isConnectingNow ?? false)")
        return parts.joined(separator: "|")
    }
}

/// Writes each queued move to the log with what the screen showed at that moment.
@MainActor
final class CorpseEnqueueReporter {
    private weak var phone: CorpseSimPhone?

    init(phone: CorpseSimPhone) {
        self.phone = phone
    }

    func report(_ kind: SyncPendingOperationKind) {
        guard let phone else { return }
        let screen = phone.viewModel.map { "\($0.phase)" } ?? "no app"
        phone.log.add("\(phone.name) queued \(kind.rawValue) [\(screen)]")
    }
}
