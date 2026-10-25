import Observation
import PencilKit
import UIKit

/// Drawing together while both partners have the canvas open, and watching the
/// partner draw from the Home tab. Strokes stream to the partner through the
/// relay while they are drawn, and the finished strokes follow so both canvases
/// end up the same. Sending to the widgets stays a separate step, as before.
@MainActor
@Observable
final class WidgetLiveDrawing {
    /// Live points go out at most this often.
    private static let sendInterval: TimeInterval = 1.0 / 30
    /// How long to wait before trying again to apply the partner's strokes while
    /// a stroke is still in progress here.
    nonisolated private static let busyRetryDelay: Duration = .milliseconds(50)
    /// After an erase ends, PencilKit can still be finishing it. The partner's
    /// strokes that arrived during a stroke wait this long after it.
    private static let afterTouchDelay: Duration = .milliseconds(150)

    /// What the partner is doing right now.
    private(set) var partnerActivity: WidgetLivePresence.PartnerActivity = .away
    /// Watching only: the partner's canvas has arrived and is on screen.
    private(set) var isShowingPartnerCanvas = false
    /// Watching only: the partner's whole canvas arrived as a snapshot since this
    /// phone or the partner last connected, so it holds every stroke. A canvas
    /// left over from before a drop can miss strokes even when it is not empty.
    private(set) var isPartnerCanvasCaughtUp = false
    /// Watching only: a stroke of the partner's is on screen, finished or still
    /// being drawn.
    private(set) var hasPartnerStrokes = false
    /// Drawing only: the watching partner asked for this whole canvas and got it
    /// since either phone last joined, so they see the strokes as they are drawn.
    private(set) var hasSentCanvasToPartner = false

    /// Called with the canvas drawing plus the partner's latest strokes. The view
    /// model puts it on the canvas.
    @ObservationIgnored var applyRemoteDrawing: ((PKDrawing) -> Void)?
    /// Keys of the strokes in the drawing on the widgets.
    @ObservationIgnored var savedStrokeKeys: (() -> Set<String>)?
    /// Called with the canvas before joining replaces it, when it held unsent
    /// strokes that do not join the shared canvas (an old draft).
    @ObservationIgnored var setAsideDrawing: ((PKDrawing) -> Void)?
    /// The view model's drawing. It is newer than `canvasView.drawing` right
    /// after a replace, because the canvas view picks that up on the next
    /// SwiftUI update.
    @ObservationIgnored var currentDrawing: (() -> PKDrawing)?
    /// The partner may have missed what this phone sent: this phone connected to
    /// a room the partner was in, or the partner joined. A game sends its whole
    /// state again.
    @ObservationIgnored var onPartnerArrived: (() -> Void)?

    @ObservationIgnored private(set) var role: WidgetLivePresence.Role
    /// The socket. A game opens its `GameLiveChannel` on it.
    @ObservationIgnored let connection: WidgetLiveConnection
    @ObservationIgnored private var presence = WidgetLivePresence()
    @ObservationIgnored private var room = WidgetLiveRoom()
    @ObservationIgnored private var playback = WidgetLivePlayback()
    @ObservationIgnored private var tracker = WidgetLiveStrokeTracker()
    @ObservationIgnored private weak var canvasView: PKCanvasView?
    @ObservationIgnored private var isConnected = false
    /// Joined a room someone was already in, and waiting for their canvas.
    @ObservationIgnored private var isAwaitingRoomState = false
    /// The partner asked for this canvas before it was on screen, such as right
    /// after a relaunch. It goes out once the canvas is attached.
    @ObservationIgnored private var isSnapshotOwed = false
    @ObservationIgnored private var pendingRemote: [WidgetLiveMessage] = []
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var outgoing: WidgetLiveOutgoingStroke?
    /// The partner's strokes waited for a stroke here, so they wait a little
    /// longer once it ends.
    @ObservationIgnored private var heldForStroke = false
    /// Live strokes that finished here and are waiting for the `ops` message
    /// that carries their real strokes.
    @ObservationIgnored private var endedLiveIDs: [String] = []
    /// Strokes that came from the partner while this screen is open. After a
    /// reconnect they are never sent back as unsent strokes from this phone,
    /// so a stroke the partner erased meanwhile stays erased.
    @ObservationIgnored private var receivedKeys: Set<String> = []
    /// Strokes drawn on this phone while this screen is open.
    @ObservationIgnored private var drawnHereKeys: Set<String> = []
    /// Strokes removed on this phone while this screen is open. A snapshot lists
    /// them, so a partner who missed the removal while away does not send the
    /// stroke back as their own unsent one.
    @ObservationIgnored private var removedHereKeys: Set<String> = []

    init(
        connection: WidgetLiveConnection,
        role: WidgetLivePresence.Role = .drawing,
        presence: WidgetLivePresence = WidgetLivePresence()
    ) {
        self.connection = connection
        self.role = role
        self.presence = presence
        connection.onMessage = { [weak self] message in
            self?.handle(message)
        }
        connection.onDisconnect = { [weak self] in
            self?.handleDisconnect()
        }
    }

    convenience init(coupleID: UUID, role: WidgetLivePresence.Role = .drawing) {
        self.init(connection: WidgetLiveConnection(coupleID: coupleID), role: role)
    }

    func start(drawing: PKDrawing = PKDrawing()) {
        tracker.reset(to: drawing)
        connection.start()
    }

    func stop() {
        connection.stop()
        retryTask?.cancel()
        handleDisconnect()
    }

    /// Draw & Guess swaps the roles between rounds on one open connection. The
    /// partner is told with a new `hello`, and what the old role was showing goes.
    func switchRole(to newRole: WidgetLivePresence.Role) {
        guard newRole != role else {
            return
        }
        role = newRole
        room.clear()
        isPartnerCanvasCaughtUp = false
        hasSentCanvasToPartner = false
        isSnapshotOwed = false
        playback.removeAll()
        pendingRemote = []
        isAwaitingRoomState = false
        updatePresence()
        if isConnected {
            sendHello(needsCanvas: newRole == .watching && presence.peerCount > 0)
        }
    }

    func attach(to canvasView: PKCanvasView) {
        guard self.canvasView !== canvasView else {
            return
        }
        self.canvasView = canvasView
        (canvasView as? PaeoniaDrawingCanvasView)?.addInkObserver { [weak self] event in
            self?.inkEvent(event)
        }
        if isSnapshotOwed, role == .drawing, isConnected, presence.peerCount > 0 {
            sendSnapshot()
        }
    }

    // MARK: - Local changes

    /// A person changed the drawing here (a stroke, the eraser, undo, or clear).
    func localDrawingDidChange(_ drawing: PKDrawing, side: CGFloat) {
        let changes = tracker.changes(to: drawing)
        let upsertKeys = changes.upserts.map(WidgetLiveStrokeSync.key(for:))
        drawnHereKeys.formUnion(upsertKeys)
        removedHereKeys.subtract(upsertKeys)
        removedHereKeys.formUnion(changes.removals)
        guard isConnected, presence.peerCount > 0, !changes.isEmpty else {
            return
        }
        let ended = endedLiveIDs
        endedLiveIDs = []
        send(ops: changes.upserts, removals: changes.removals, side: side, ended: ended)
    }

    /// The drawing changed from code (a load, a resize, or the partner's
    /// strokes). Nothing to send.
    func drawingReplacedFromCode(_ drawing: PKDrawing) {
        tracker.reset(to: drawing)
    }

    /// Changes when the partner's canvas changes (watching only).
    var roomVersion: Int { room.version }
    /// Watching only: the partner's whole canvas so far, at `WidgetLiveRoom.side`.
    var partnerCanvasDrawing: PKDrawing? { room.drawing }
    /// The partner is in the middle of a stroke, or one is still fading out.
    var hasLiveStrokes: Bool { !playback.isEmpty }

    /// Changes whenever the overlay may need to draw again, so it can sleep
    /// between the partner's strokes.
    private(set) var overlayRevision = 0

    /// Watching only: the partner's canvas, for a view of `side` points.
    func roomStrokes(side: CGFloat) -> [PKStroke] {
        room.strokes(side: side)
    }

    /// In both roles: the strokes the partner is drawing right now, at `now`.
    func liveStrokes(at now: TimeInterval, side: CGFloat) -> [PKStroke] {
        playback.prune(now: now)
        return playback.isEmpty ? [] : playback.pencilKitStrokes(at: now, side: side)
    }

    // MARK: - Messages

    private func handle(_ message: WidgetLiveMessage) {
        switch message.type {
        case .welcome, .joined, .hello, .left:
            handlePresence(message)
        case .live:
            playback.receive(message, now: CACurrentMediaTime())
        case .liveEnd:
            if let id = message.id {
                playback.end(id, now: CACurrentMediaTime())
            }
        case .ops where role != .drawing:
            room.apply(message, upserts: Self.upserts(in: message, side: WidgetLiveRoom.side))
            if message.snapshot == true {
                isPartnerCanvasCaughtUp = true
            }
            playback.remove(message.ended ?? [])
        case .ops:
            pendingRemote.append(message)
            applyPendingRemote()
        }
        updatePresence()
    }

    private func handlePresence(_ message: WidgetLiveMessage) {
        switch message.type {
        case .welcome:
            isConnected = true
            isPartnerCanvasCaughtUp = false
            hasSentCanvasToPartner = false
            presence.welcome(id: message.id, peers: message.peers ?? 0)
            isAwaitingRoomState = role == .drawing && presence.peerCount > 0
            sendHello(needsCanvas: presence.peerCount > 0)
            announceArrivalIfPartnerIsHere()
        case .joined:
            // The partner may be back after a drop the relay never saw, with
            // strokes drawn while away. Their whole canvas is asked for again.
            presence.joined()
            isPartnerCanvasCaughtUp = false
            hasSentCanvasToPartner = false
            sendHello(needsCanvas: role == .watching)
            announceArrivalIfPartnerIsHere()
        case .hello:
            if let from = message.from, let peerRole = message.role.flatMap(WidgetLivePresence.Role.init) {
                presence.hello(from: from, role: peerRole)
                // The partner started drawing on a connection that was already open.
                if role == .watching, peerRole == .drawing, !isPartnerCanvasCaughtUp {
                    sendHello(needsCanvas: true)
                }
            }
            if role == .drawing, message.needsCanvas == true {
                sendSnapshot()
            }
        case .left:
            presence.left(id: message.id)
        case .live, .liveEnd, .ops:
            break
        }
    }

    private func announceArrivalIfPartnerIsHere() {
        if presence.peerCount > 0 {
            onPartnerArrived?()
        }
    }

    private func handleDisconnect() {
        isConnected = false
        isSnapshotOwed = false
        isPartnerCanvasCaughtUp = false
        hasSentCanvasToPartner = false
        presence.reset()
        outgoing = nil
        endedLiveIDs = []
        updatePresence()
    }

    private func updatePresence() {
        partnerActivity = presence.partnerActivity
        if partnerActivity != .watching {
            hasSentCanvasToPartner = false
        }
        if presence.peerCount == 0 {
            playback.removeAll()
            isAwaitingRoomState = false
        }
        // The partner left the canvas. The Home tab shows the widget again.
        if partnerActivity != .drawing {
            room.clear()
            isPartnerCanvasCaughtUp = false
        }
        isShowingPartnerCanvas = room.drawing != nil
        hasPartnerStrokes = room.drawing?.strokes.isEmpty == false || !playback.isEmpty
        overlayRevision &+= 1
    }

    private func sendHello(needsCanvas: Bool) {
        connection.send(WidgetLiveMessage(
            type: .hello,
            needsCanvas: needsCanvas ? true : nil,
            from: presence.ownID,
            role: role.rawValue
        ))
    }

}

// MARK: - Sending and applying strokes

extension WidgetLiveDrawing {
    /// Someone asked for this canvas. They take it as it is, also when it is
    /// empty, so strokes erased here do not come back from their phone.
    private func sendSnapshot() {
        guard let canvasView, let currentDrawing else {
            isSnapshotOwed = true
            return
        }
        isSnapshotOwed = false
        send(
            ops: currentDrawing().strokes,
            removals: removedHereKeys.sorted(),
            side: Self.side(of: canvasView),
            ended: [],
            snapshot: true
        )
        hasSentCanvasToPartner = true
    }

    private func send(
        ops upserts: [PKStroke],
        removals: [String],
        side: CGFloat,
        ended: [String],
        snapshot: Bool = false
    ) {
        connection.send(WidgetLiveMessage(
            type: .ops,
            side: Double(side),
            upserts: upserts.isEmpty ? nil : PKDrawing(strokes: upserts).dataRepresentation().base64EncodedString(),
            removals: removals.isEmpty ? nil : removals,
            ended: ended.isEmpty ? nil : ended,
            snapshot: snapshot ? true : nil
        ))
    }

    /// Puts the partner's finished strokes on the canvas. Waits while a stroke
    /// is in progress here, because replacing the drawing would cut it off.
    private func applyPendingRemote() {
        guard !pendingRemote.isEmpty, let canvasView, let currentDrawing else {
            return
        }
        guard !Self.isStrokeInProgress(on: canvasView) else {
            heldForStroke = true
            applyPendingRemoteSoon()
            return
        }
        if heldForStroke {
            heldForStroke = false
            applyPendingRemoteSoon(after: Self.afterTouchDelay)
            return
        }

        let side = Self.side(of: canvasView)
        // Send any change made here first, so it is never mistaken for the
        // partner's and dropped.
        let local = currentDrawing()
        localDrawingDidChange(local, side: side)

        var merged = local
        var ownUnsent: [PKStroke] = []
        for message in pendingRemote {
            let upserts = Self.upserts(in: message, side: side)
            let upsertKeys = upserts.map(WidgetLiveStrokeSync.key(for:))
            receivedKeys.formUnion(upsertKeys)
            removedHereKeys.subtract(upsertKeys)
            if message.snapshot == true, isAwaitingRoomState {
                (merged, ownUnsent) = join(message, upserts: upserts, into: merged)
            } else {
                merged = WidgetLiveStrokeSync.apply(upserts: upserts, removals: message.removals ?? [], to: merged)
            }
            playback.remove(message.ended ?? [])
        }
        pendingRemote = []
        overlayRevision &+= 1
        applyRemoteDrawing?(merged)
        if !ownUnsent.isEmpty {
            send(ops: ownUnsent, removals: [], side: side, ended: [])
        }
    }

    /// Takes the canvas of the room this phone joined, plus the strokes drawn
    /// here that it lacks.
    private func join(
        _ message: WidgetLiveMessage,
        upserts: [PKStroke],
        into local: PKDrawing
    ) -> (drawing: PKDrawing, ownUnsent: [PKStroke]) {
        isAwaitingRoomState = false
        let joined = WidgetLiveStrokeSync.join(
            room: upserts,
            local: local,
            savedKeys: (savedStrokeKeys?() ?? []).union(receivedKeys),
            drawnHereKeys: drawnHereKeys,
            roomRemovals: Set(message.removals ?? [])
        )
        if joined.hasOtherUnsentStrokes {
            setAsideDrawing?(local)
        }
        return (joined.drawing, joined.ownUnsent)
    }

    /// The drawing must not be replaced while a stroke is drawn here, or while
    /// PencilKit is still finishing an erase.
    private func applyPendingRemoteSoon(after delay: Duration = busyRetryDelay) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
            self?.applyPendingRemote()
        }
    }
}

// MARK: - Ink and helpers

extension WidgetLiveDrawing {
    /// A pen or pencil stroke on this canvas. The partner sees it while it is
    /// drawn, and its finished stroke follows in the next `ops`.
    private func inkEvent(_ event: InkEvent) {
        switch event {
        case let .began(stroke):
            outgoing = nil
            guard isConnected, presence.peerCount > 0, let canvasView else {
                return
            }
            outgoing = WidgetLiveOutgoingStroke(side: Self.side(of: canvasView))
            flushOutgoing(stroke)
        case let .changed(stroke):
            if CACurrentMediaTime() - (outgoing?.lastSentAt ?? 0) >= Self.sendInterval {
                flushOutgoing(stroke)
            }
        case let .ended(stroke):
            // Sent before the canvas adds the stroke, so the `ops` that
            // carries it names this live stroke in `ended`.
            guard let id = outgoing?.id else {
                return
            }
            flushOutgoing(stroke)
            connection.send(WidgetLiveMessage(type: .liveEnd, id: id))
            endedLiveIDs.append(id)
            outgoing = nil
        }
    }

    private func flushOutgoing(_ stroke: InkStroke) {
        if let message = outgoing?.takeMessage(from: stroke, now: CACurrentMediaTime()) {
            connection.send(message)
        }
    }

    /// The message's strokes, scaled from the sender's canvas to this one.
    private static func upserts(in message: WidgetLiveMessage, side: CGFloat) -> [PKStroke] {
        guard let drawing = message.preparedUpserts ?? message.decodeUpserts() else {
            return []
        }
        return drawing.scaled(fromSide: CGFloat(message.side ?? Double(side)), toSide: side).strokes
    }

    private static func side(of canvasView: PKCanvasView) -> CGFloat {
        WidgetDrawingViewModel.canvasSide(for: canvasView.bounds.size)
    }

    private static func isStrokeInProgress(on canvasView: PKCanvasView) -> Bool {
        (canvasView as? PaeoniaDrawingCanvasView)?.isStrokeInProgress ?? false
    }
}
