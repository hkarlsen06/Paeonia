import Foundation
import PencilKit
@testable import PaeoniaApp

/// The drawer's PencilKit canvas on screen, standing in for `PencilKitCanvasView`.
/// It applies drawings the board replaced from code, as `updateUIView` does, and
/// reports strokes drawn on it the way the canvas delegate does.
@MainActor
final class SimCanvas {
    let view: PKCanvasView
    let side: CGFloat
    private let board: DrawAndGuessDrawingBoard
    private var appliedRevision = -1

    init(viewModel: DrawAndGuessViewModel, side: CGFloat) {
        self.side = side
        board = viewModel.board
        view = PKCanvasView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        sync()
        viewModel.canvasReady(view)
        board.canvasDidLayout(side: side)
        sync()
    }

    /// SwiftUI's update pass.
    func sync() {
        guard appliedRevision != board.drawingRevision else { return }
        view.drawing = board.drawing
        appliedRevision = board.drawingRevision
        board.canvasDidApplyDrawing(revision: appliedRevision)
    }

    func draw(_ stroke: PKStroke) {
        sync()
        board.setStrokeInProgress(true)
        let drawing = PKDrawing(strokes: view.drawing.strokes + [stroke])
        view.drawing = drawing
        board.updateDrawing(drawing, undoManager: nil)
        board.setStrokeInProgress(false)
    }

    func erase(strokeAt index: Int) {
        sync()
        var strokes = view.drawing.strokes
        guard strokes.indices.contains(index) else { return }
        strokes.remove(at: index)
        let drawing = PKDrawing(strokes: strokes)
        view.drawing = drawing
        board.updateDrawing(drawing, undoManager: nil)
    }
}

/// One phone: its own Games cache, pending operations, drawings on disk and
/// relay socket, a real `GamesViewModel` and `DrawAndGuessViewModel` wired as
/// `GamesDependencies.live()` and `PaeoniaSyncServiceDefaults` wire them, a sync
/// that runs the real drain, and a stand-in for the live feed.
///
/// The stores outlive a force quit. The view models, the tasks and the socket do not.
@MainActor
final class SimPhone {
    let name: String
    let userID: UUID
    let partnerID: UUID
    let server: SimServer
    let relay: SimRelay
    let clock: SimClock
    let log: SimLog
    let network: SimNetwork
    let canvasSide: CGFloat

    // What a force quit keeps.
    let cache = InMemoryGamesCache()
    let pending = SimPendingStore()
    let drawingStore = InMemoryGameDrawingStore()
    let operations: SimOperationProvider

    // One app launch.
    private(set) var viewModel: DrawAndGuessViewModel?
    private(set) var games: GamesViewModel?
    private(set) var socket: SimRelaySocket?
    private(set) var canvas: SimCanvas?
    private var gateway: SimGateway?
    private var drain: PendingSyncOperationDrainStream?
    private var appTasks: [Task<Void, Never>] = []
    private var startTask: Task<Void, Never>?

    private(set) var isAlive = false
    private(set) var isScreenOpen = false
    private(set) var isForeground = true

    // The live feed stand-in.
    /// The subscription is down although the phone is online.
    var isFeedOutage = false
    /// Delivers states one at a time and late, so an older state can land after a newer read.
    var isFeedDelayed = false
    private var feedQueue: [RemoteDrawAndGuessState] = []
    private var feedCapturedVersion = -1
    private var feedWasUp = false

    // The sync.
    private var syncTask: Task<Void, Never>?
    private var syncFollowUp = false

    /// Notices the screens showed, in order.
    private(set) var notices: [GamesNotice] = []
    /// Rounds whose canvas was restored after a relaunch, for the draft check.
    var launchCount = 0

    init(
        name: String,
        userID: UUID,
        partnerID: UUID,
        server: SimServer,
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
        let pending = pending
        let reporter = SimEnqueueReporter(phone: self)
        Task {
            await pending.setOnEnqueue { kind, data in
                struct Round: Decodable { let roundID: UUID }
                let round = data.flatMap { try? JSONDecoder().decode(Round.self, from: $0) }?.roundID
                Task { @MainActor in reporter.report(kind, round: round) }
            }
        }
    }

    var participants: DrawAndGuessParticipants {
        DrawAndGuessParticipants(
            currentUserID: userID,
            coupleID: server.coupleID,
            partnerName: name == "A" ? "Robin" : "Alex",
            currentName: name == "A" ? "Alex" : "Robin"
        )
    }

    /// The view model while the game screen is open and the app is in front.
    var activeViewModel: DrawAndGuessViewModel? {
        isAlive && isScreenOpen && isForeground ? viewModel : nil
    }

    // MARK: - Launch and force quit

    func launch() {
        guard !isAlive else { return }
        isAlive = true
        isForeground = true
        isScreenOpen = false
        launchCount += 1
        let gateway = SimGateway(user: userID, server: server, network: network)
        let transfer = SimDrawingTransfer(user: userID, server: server, network: network)
        self.gateway = gateway
        drain = PendingSyncOperationDrainStream(handlers: [
            PickDrawWordPendingOperationHandler(gateway: gateway, cache: cache, drawingStore: drawingStore),
            SubmitGameDrawingPendingOperationHandler(
                gateway: gateway,
                transfer: transfer,
                cache: cache,
                drawingStore: drawingStore
            ),
            SubmitGameGuessPendingOperationHandler(gateway: gateway, cache: cache),
            GiveUpGameRoundPendingOperationHandler(gateway: gateway, cache: cache),
            SaveGameRoundPendingOperationHandler(
                gateway: gateway,
                mediaUploader: SimMemoryUploader(user: userID, server: server, network: network),
                cache: cache,
                transfer: transfer,
                drawingStore: drawingStore
            ),
        ])
        let clock = clock
        let dependencies = GamesDependencies(
            gateway: gateway,
            cache: cache,
            pendingOperationStore: pending,
            operationProvider: operations,
            drawingStore: drawingStore,
            drawingTransfer: transfer,
            makeLive: { [weak self] _ in self?.makeLiveRoom() },
            now: { clock.now }
        )
        // The heartbeat and the tick run as the driver moves the clock, so their own timers never fire.
        let viewModel = DrawAndGuessViewModel(
            dependencies: dependencies,
            heartbeatInterval: .seconds(36_000),
            tickInterval: .seconds(36_000),
            sleep: { try await Task.sleep(for: $0 / 1_000) }
        )
        let games = GamesViewModel(dependencies: dependencies, drawAndGuess: viewModel)
        games.configure(participants: participants)
        games.setLocalChangeSyncHandler { [weak self] in await self?.sync() }
        self.viewModel = viewModel
        self.games = games
        appTasks = [
            Task { await games.load() },
            Task { await games.observeStoreChanges() },
        ]
        feedWasUp = false
        log.add("\(name) launch #\(launchCount)")
        // The sync service runs once at launch.
        Task { await self.sync() }
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
        self.socket = socket
        return WidgetLiveDrawing(connection: socket, role: .watching)
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
        for task in appTasks {
            task.cancel()
        }
        appTasks = []
        if let viewModel {
            viewModel.cancelTasks()
            viewModel.heartbeatTask?.cancel()
            viewModel.heartbeatTask = nil
            viewModel.liveObservationTask?.cancel()
            viewModel.liveObservationTask = nil
            viewModel.isRunning = false
            viewModel.isStopped = true
        }
        if let socket {
            if closesSocket {
                socket.stop()
            } else {
                socket.dropSilently()
                socket.stop()
            }
        }
        canvas = nil
        socket = nil
        viewModel = nil
        games = nil
        gateway = nil
        drain = nil
        isScreenOpen = false
    }

    /// Stops everything at the end of a run, so no task outlives the test.
    func shutDown() {
        if isScreenOpen {
            viewModel?.stop()
        }
        forceQuit(closesSocket: true)
        network.releaseHeld(deliverAll: true)
    }

    // MARK: - Screen and app state

    func openScreen() {
        guard isAlive, !isScreenOpen, let viewModel else { return }
        isScreenOpen = true
        log.add("\(name) open screen")
        startTask = Task { await viewModel.start() }
    }

    func closeScreen() {
        guard isAlive, isScreenOpen, let viewModel else { return }
        log.add("\(name) close screen")
        canvas = nil
        startTask?.cancel()
        startTask = nil
        viewModel.stop()
        isScreenOpen = false
    }

    func moveToBackground() {
        guard isAlive, isForeground else { return }
        log.add("\(name) background")
        isForeground = false
        if isScreenOpen {
            viewModel?.scenePhaseChanged(isActive: false)
        }
    }

    func moveToForeground() {
        guard isAlive, !isForeground else { return }
        log.add("\(name) foreground")
        isForeground = true
        if isScreenOpen {
            viewModel?.scenePhaseChanged(isActive: true)
        }
        if let games {
            Task { await games.refresh() }
        }
        Task { await self.sync() }
    }

    func setOnline(_ online: Bool) {
        guard network.isOnline != online else { return }
        network.isOnline = online
        log.add("\(name) \(online ? "online" : "offline")")
        if !online {
            socket?.dropSilently()
        } else if isAlive {
            Task { await self.sync() }
        }
    }

    /// The open screen's 30-second heartbeat, which the driver runs as it moves the clock.
    func heartbeat() {
        guard let viewModel = activeViewModel, let gateway else { return }
        Task { try? await gateway.setPresence(true) }
        viewModel.now = clock.now
        viewModel.recompute()
    }

    /// The view model's 15-second tick and the hub's.
    func tick() {
        guard isAlive, let viewModel else { return }
        viewModel.now = clock.now
        if isScreenOpen {
            viewModel.recompute()
        }
    }

    // MARK: - Sync

    /// One sync run, like `PaeoniaSyncService.performRun`: in-flight writes go
    /// back to retrying, then the drain sends everything that waits. A request
    /// during a run asks for one more run after it.
    func sync() async {
        guard isAlive else { return }
        if let syncTask {
            syncFollowUp = true
            await syncTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                syncFollowUp = false
                await runSyncOnce()
            } while syncFollowUp && !Task.isCancelled && isAlive
        }
        syncTask = task
        await task.value
        if syncTask == task {
            syncTask = nil
        }
    }

    var isSyncing: Bool {
        syncTask != nil
    }

    private func runSyncOnce() async {
        guard let drain else { return }
        try? await pending.resetInFlight(ownerUserID: userID)
        let context = SyncContext(
            session: SyncSession(userID: userID),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pending
        )
        try? await drain.push(context: context)
    }

    // MARK: - Live feed

    /// Delivers the server's state as the `games:get_draw_and_guess` subscription would.
    func feedTick() async {
        let isUp = isAlive && isForeground && network.isOnline && !isFeedOutage
        guard isUp else {
            feedWasUp = false
            return
        }
        if !feedWasUp {
            // A new subscription starts from the current value.
            feedWasUp = true
            feedQueue = []
            feedCapturedVersion = -1
        }
        if server.viewVersion != feedCapturedVersion {
            feedCapturedVersion = server.viewVersion
            feedQueue.append(server.view(for: userID))
        }
        guard !feedQueue.isEmpty else { return }
        let state: RemoteDrawAndGuessState
        if isFeedDelayed {
            state = feedQueue.removeFirst()
        } else {
            state = feedQueue.removeLast()
            feedQueue = []
        }
        await cache.saveState(state, ownerUserID: userID)
        LocalStoreChanges.post(.games, ownerUserID: userID)
    }

    var feedHasBacklog: Bool {
        !feedQueue.isEmpty || feedCapturedVersion != server.viewVersion
    }

    // MARK: - Screens

    /// SwiftUI's part: the canvas exists while the drawing screen shows, and a
    /// notice goes to the banner once.
    func updateScreens() {
        guard isAlive else { return }
        if let viewModel, isScreenOpen, viewModel.phase == .drawing {
            if canvas == nil {
                canvas = SimCanvas(viewModel: viewModel, side: canvasSide)
            }
            canvas?.sync()
        } else {
            canvas = nil
        }
        if let notice = viewModel?.notice {
            notices.append(notice)
            log.add("\(name) notice \(notice)")
            viewModel?.clearNotice()
        }
        if let notice = games?.notice {
            notices.append(notice)
            log.add("\(name) hub notice \(notice)")
            games?.clearNotice()
        }
    }

    func reconnectRelay() {
        socket?.reconnectIfNeeded()
    }

    /// The phone's view of the world, for spotting when it stopped changing.
    func fingerprint() async -> String {
        let queue = await pending.fingerprint(ownerUserID: userID)
        let document = await cache.document(ownerUserID: userID)
        var parts = [queue, "\(document.state?.game?.version ?? -1)", "\(document.notices.count)"]
        if let viewModel {
            parts += [
                "\(viewModel.phase)",
                "\(viewModel.round?.id.uuidString.prefix(6) ?? "-")",
                "\(viewModel.round?.state.rawValue ?? "-")",
                "\(viewModel.isReplayReady)",
                "\(viewModel.isLoadingDrawing)",
                "\(viewModel.loadedDrawingVersion)",
                "\(viewModel.partnerPresence)",
                "\(viewModel.savePrompt)",
                "\(viewModel.isShowingWrongGuess)",
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
final class SimEnqueueReporter {
    private weak var phone: SimPhone?

    init(phone: SimPhone) {
        self.phone = phone
    }

    func report(_ kind: SyncPendingOperationKind, round: UUID?) {
        guard let phone else { return }
        let model = phone.viewModel
        let screen = model.map { "\($0.phase)" } ?? "no app"
        let shown = model?.round?.id.uuidString.prefix(6) ?? "-"
        let sent = model?.round?.isDrawingSent ?? false
        let drawings = model?.pending.drawings.count ?? -1
        phone.log.add(
            "\(phone.name) queued \(kind.rawValue) for \(round?.uuidString.prefix(6) ?? "-") "
                + "[\(screen) round \(shown) sent \(sent) queued drawings \(drawings)]"
        )
    }
}
