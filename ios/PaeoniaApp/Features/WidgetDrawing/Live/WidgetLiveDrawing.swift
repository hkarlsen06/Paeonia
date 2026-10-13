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
    /// After a touch ends, PencilKit can still be finishing the stroke or the
    /// erase. The partner's strokes wait this long so they never replace it.
    private static let afterTouchDelay: Duration = .milliseconds(150)

    /// What the partner is doing right now.
    private(set) var partnerActivity: WidgetLivePresence.PartnerActivity = .away
    /// Watching only: the partner's canvas has arrived and is on screen.
    private(set) var isShowingPartnerCanvas = false
    /// Watching only: the partner's whole canvas arrived as a snapshot since this
    /// phone or the partner last connected, so it holds every stroke. A canvas
    /// left over from before a drop can miss strokes even when it is not empty.
    private(set) var isPartnerCanvasCaughtUp = false
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

    @ObservationIgnored private(set) var role: WidgetLivePresence.Role
    @ObservationIgnored private let connection: WidgetLiveConnection
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
    @ObservationIgnored private var calibration = WidgetLiveInkCalibration.load()
    /// Ink and width of the stroke being drawn here. Its real stroke teaches
    /// `calibration` once PencilKit commits it.
    @ObservationIgnored private var strokeToCalibrate: (key: String, width: CGFloat)?
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

    init(connection: WidgetLiveConnection, role: WidgetLivePresence.Role = .drawing) {
        self.connection = connection
        self.role = role
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
        let recognizer = WidgetLiveTouchRecognizer()
        recognizer.onBegan = { [weak self] touch, event in
            self?.touchBegan(touch, event: event)
        }
        recognizer.onMoved = { [weak self] touch, event in
            self?.touchMoved(touch, event: event)
        }
        recognizer.onEnded = { [weak self] cancelled in
            self?.touchEnded(cancelled: cancelled)
        }
        canvasView.addGestureRecognizer(recognizer)
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
        calibrate(from: changes.upserts)
        guard isConnected, presence.peerCount > 0, !changes.isEmpty else {
            return
        }
        var ended = endedLiveIDs
        endedLiveIDs = []
        // PencilKit can commit the stroke before the touch-ended callback runs.
        if let id = outgoing?.id {
            ended.append(id)
            outgoing?.isPartOfOps = true
        }
        send(ops: changes.upserts, removals: changes.removals, side: side, ended: ended)
    }

    /// Learns from the stroke that was just drawn here, also while the partner
    /// is away, so the first live stroke they see already has the right size.
    private func calibrate(from upserts: [PKStroke]) {
        guard let (key, width) = strokeToCalibrate,
              let stroke = upserts.max(by: { $0.path.creationDate < $1.path.creationDate })
        else {
            return
        }
        strokeToCalibrate = nil
        calibration.record(ink: key, width: width, stroke: stroke)
        calibration.save()
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

    /// What the overlay shows at `now`: when watching, the partner's canvas,
    /// and in both roles the strokes the partner is drawing right now.
    func overlayStrokes(at now: TimeInterval, side: CGFloat) -> [PKStroke] {
        playback.prune(now: now)
        var strokes = room.strokes(side: side)
        if !playback.isEmpty {
            strokes += playback.pencilKitStrokes(at: now, side: side)
        }
        return strokes
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
        case .joined:
            // The partner may be back after a drop the relay never saw, with
            // strokes drawn while away. Their whole canvas is asked for again.
            presence.joined()
            isPartnerCanvasCaughtUp = false
            hasSentCanvasToPartner = false
            sendHello(needsCanvas: role == .watching)
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
            applyPendingRemoteSoon()
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

    /// PencilKit may commit a lifted stroke a moment after the touch ends, and
    /// the drawing must not be replaced before that.
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

// MARK: - Touches and helpers

extension WidgetLiveDrawing {
    private func touchBegan(_ touch: UITouch, event: UIEvent) {
        outgoing = nil
        guard let canvasView, let tool = canvasView.tool as? PKInkingTool else {
            strokeToCalibrate = nil
            return
        }
        let key = WidgetLiveInkCalibration.key(ink: tool.ink.inkType.rawValue, isPencil: touch.type == .pencil)
        strokeToCalibrate = (key, tool.width)
        guard isConnected, presence.peerCount > 0 else {
            return
        }
        outgoing = WidgetLiveOutgoingStroke(
            touch: touch,
            tool: tool,
            side: Self.side(of: canvasView),
            style: calibration.style(ink: key, width: tool.width)
        )
        outgoing?.append(touch, event: event, in: canvasView)
        flushOutgoing()
    }

    private func touchMoved(_ touch: UITouch, event: UIEvent) {
        guard let canvasView, outgoing != nil else {
            return
        }
        outgoing?.append(touch, event: event, in: canvasView)
        if CACurrentMediaTime() - (outgoing?.lastSentAt ?? 0) >= Self.sendInterval {
            flushOutgoing()
        }
    }

    private func touchEnded(cancelled: Bool) {
        if let stroke = outgoing {
            flushOutgoing()
            connection.send(WidgetLiveMessage(type: .liveEnd, id: stroke.id))
            if !cancelled, !stroke.isPartOfOps {
                endedLiveIDs.append(stroke.id)
            }
            outgoing = nil
        }
        applyPendingRemoteSoon(after: Self.afterTouchDelay)
    }

    private func flushOutgoing() {
        if let message = outgoing?.takeMessage(now: CACurrentMediaTime()) {
            connection.send(message)
        }
    }

    /// The message's strokes, scaled from the sender's canvas to this one.
    private static func upserts(in message: WidgetLiveMessage, side: CGFloat) -> [PKStroke] {
        guard let encoded = message.upserts,
              let data = Data(base64Encoded: encoded),
              let drawing = try? PKDrawing(data: data)
        else {
            return []
        }
        return drawing.scaled(fromSide: CGFloat(message.side ?? Double(side)), toSide: side).strokes
    }

    private static func side(of canvasView: PKCanvasView) -> CGFloat {
        WidgetDrawingViewModel.canvasSide(for: canvasView.bounds.size)
    }

    private static func isStrokeInProgress(on canvasView: PKCanvasView) -> Bool {
        switch canvasView.drawingGestureRecognizer.state {
        case .began, .changed:
            true
        default:
            false
        }
    }
}
