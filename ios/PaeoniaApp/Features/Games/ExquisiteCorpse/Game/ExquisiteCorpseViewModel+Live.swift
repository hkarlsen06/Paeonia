import Observation
import PencilKit
import UIKit

// The relay room. The game uses it for roles, so each phone knows what the other
// is doing, and for `ExquisiteCorpseLiveMessage`: where the drawer's pen is, the
// strip so far, and Done.
//
// The drawer's canvas is never attached to the room (`WidgetLiveDrawing.attach`)
// and the room is never told about changes to it (`localDrawingDidChange`), so
// the relay's own `live` and `ops` stroke messages never carry the part above the
// fold.
extension ExquisiteCorpseViewModel {
    // MARK: - Room

    func attach(_ room: WidgetLiveDrawing) {
        room.applyRemoteDrawing = { _ in }
        room.savedStrokeKeys = { [] }
        room.setAsideDrawing = { _ in }
        // The room asks for the canvas to answer a snapshot request. It has no
        // canvas here, and the answer is empty even if that changes.
        room.currentDrawing = { PKDrawing() }
        room.onPartnerArrived = { [weak self] in self?.resendLiveState() }
        let channel = GameLiveChannel<ExquisiteCorpseLiveMessage>(connection: room.connection)
        channel.onMessage = { [weak self] message in self?.receive(message) }
        self.channel = channel
        live = room
    }

    func startLive() {
        guard let live else { return }
        live.start(drawing: PKDrawing())
        liveObservationTask?.cancel()
        liveObservationTask = Task { [weak self] in
            let activity = Observations { live.partnerActivity }
            for await _ in activity {
                guard !Task.isCancelled, let self else { return }
                recompute()
            }
        }
    }

    func stopLive() {
        liveObservationTask?.cancel()
        liveObservationTask = nil
        live?.stop()
    }

    /// The partner is in the room, whatever they are doing.
    var isPartnerInRoom: Bool {
        (live?.partnerActivity ?? .away) != .away
    }

    /// What this phone tells the partner's phone. A drawer whose part is queued on
    /// this phone and not on the server yet stays `drawing`, so the watcher keeps
    /// the folded paper through the hand-off.
    var liveRole: WidgetLivePresence.Role {
        let isHandingOff = isWaitingToSend && (phase == .waiting || phase == .watching || phase == .waitingToSync)
        return isHandingOff ? .drawing : ExquisiteCorpsePhase.liveRole(phase: phase)
    }

    func syncLiveRole() {
        // The part left the queue, so the server has it and Done is old news.
        if let sent = doneSentPartID, !pending.parts.contains(where: { $0.partID == sent }) {
            doneSentPartID = nil
        }
        live?.switchRole(to: liveRole)
    }

    // MARK: - Sending

    /// The drawer's canvas appeared. Binds the board and listens to the pen and
    /// the strokes. The room itself is never attached to this canvas.
    func canvasReady(_ canvasView: PKCanvasView) {
        board.bindCanvasView(canvasView)
        guard penCanvas !== canvasView else { return }
        penCanvas = canvasView
        addPenRecognizer(to: canvasView)
        (canvasView as? PaeoniaDrawingCanvasView)?.addInkObserver { [weak self] event in
            self?.liveInkEvent(event)
        }
    }

    private func addPenRecognizer(to canvasView: PKCanvasView) {
        let recognizer = WidgetLiveTouchRecognizer()
        // The canvas view also covers the strip above the part, so its width is
        // the part's side and not its height.
        recognizer.onBegan = { [weak self, weak canvasView] touch, _ in
            guard let self, let canvasView else { return }
            let side = canvasView.bounds.width
            penMoved(to: touch.location(in: canvasView), in: CGSize(width: side, height: side))
        }
        recognizer.onMoved = { [weak self, weak canvasView] touch, _ in
            guard let self, let canvasView else { return }
            let side = canvasView.bounds.width
            penMoved(to: touch.location(in: canvasView), in: CGSize(width: side, height: side))
        }
        recognizer.onEnded = { [weak self] _ in
            self?.penLifted()
        }
        canvasView.addGestureRecognizer(recognizer)
    }

    // MARK: - The stroke being drawn

    /// The canvas hands a stroke to the board only when the pen lifts. This
    /// sends the strip with the stroke so far, so the partner sees it reach the
    /// strip while it is drawn. Only the strip of it ever leaves the phone. The
    /// finished stroke reaches the board, which sends the strip again.
    private func liveInkEvent(_ event: InkEvent) {
        switch event {
        case let .began(stroke), let .changed(stroke):
            guard monotonicNow() - liveStrokeSentAt >= Self.liveStrokeInterval,
                  board.canvasSide > 0,
                  stroke.samples.contains(where: { $0.location.y >= ExquisiteCorpseFold.foldY(side: board.canvasSide) })
            else { return }
            liveStrokeSentAt = monotonicNow()
            sendStripIfChanged(including: stroke.pencilKitStroke())
        case let .snapChanged(stroke):
            // Always, even when the stroke stays above the fold, so the strip
            // drops any rough piece the shape no longer reaches, or gets it
            // back when the shape turns back into the drawn line.
            liveStrokeSentAt = monotonicNow()
            sendStripIfChanged(including: stroke.pencilKitStroke())
        case .ended:
            liveStrokeSentAt = 0
        }
    }

    /// How often the strip goes out while a stroke is drawn across it.
    private static let liveStrokeInterval: TimeInterval = 1.0 / 12

    /// The pen is at `point` on a canvas of `size`.
    func penMoved(to point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        penMoved(x: Double(point.x / size.width), y: Double(point.y / size.height))
    }

    /// The pen is at `x` and `y`, as fractions of the square from 0 to 1. The
    /// partner sees a coarse position at most 8 times a second.
    func penMoved(x: Double, y: Double) {
        guard phase == .drawing, isPartnerInRoom, let partID = ownPartID,
              let sample = penSampler.move(x: x, y: y, at: monotonicNow())
        else { return }
        channel?.send(.pen(partID: partID, x: sample.x, y: sample.y))
    }

    func penLifted() {
        let sample = penSampler.lift()
        guard phase == .drawing, isPartnerInRoom, let partID = ownPartID else { return }
        channel?.send(.pen(partID: partID, x: sample.x, y: sample.y))
    }

    /// Sends the strip after a change to the canvas, when the strip itself changed
    /// and the partner is there to see it. A stroke above the fold changes
    /// nothing the partner may see, so nothing goes out. `liveStroke` is a stroke
    /// still being drawn, in canvas points.
    func sendStripIfChanged(including liveStroke: PKStroke? = nil) {
        guard phase == .drawing, let part, part.hasStrip, isPartnerInRoom,
              let partID = ownPartID, boardPartID == partID
        else { return }
        let strip = stripCache.strip(of: board.drawing.strokes, including: liveStroke, fromSide: board.canvasSide)
        let signature = strip.paeoniaContentSignature
        if let sentStrip, sentStrip.partID == partID, sentStrip.signature == signature {
            return
        }
        send(strip, partID: partID)
    }

    private func send(_ strip: PKDrawing, partID: UUID) {
        sentStrip = (partID, strip.paeoniaContentSignature)
        channel?.send(.strip(partID: partID, drawing: strip.dataRepresentation().base64EncodedString()))
    }

    /// Done: the final strip, the pen lifting, and Done itself.
    func sendDoneLive(partID: UUID, strip: PKDrawing?) {
        doneSentPartID = partID
        if let strip {
            send(strip, partID: partID)
        }
        channel?.send(.pen(partID: partID, x: nil, y: nil))
        channel?.send(.done(partID: partID))
    }

    /// The partner may have missed what this phone sent: they joined, or they
    /// started watching. The strip is the whole state, so one message catches
    /// them up.
    func resendLiveState() {
        if phase == .drawing, let part, let partID = ownPartID, boardPartID == partID {
            if part.hasStrip {
                send(ExquisiteCorpseFold.strip(of: board.canonicalDrawing), partID: partID)
            }
            channel?.send(.pen(partID: partID, x: nil, y: nil))
            return
        }
        // Done was tapped, and the part has not reached the server yet. The queued
        // part has the strip.
        guard let sent = doneSentPartID, let queued = pending.parts.last(where: { $0.partID == sent }) else { return }
        if let data = queued.strip?.data, let strip = try? PKDrawing(data: data) {
            send(strip, partID: sent)
        }
        channel?.send(.pen(partID: sent, x: nil, y: nil))
        channel?.send(.done(partID: sent))
    }

    // MARK: - Receiving

    /// Takes a message of the partner's. Only the part that is open now counts,
    /// and a message about any other part is ignored. The one exception is the
    /// strip of the part just finished, which the drawing screen can still show
    /// while the strip file loads.
    func receive(_ message: ExquisiteCorpseLiveMessage) {
        switch message {
        case let .pen(partID, x, y):
            receivePen(partID: partID, x: x, y: y)
        case let .strip(partID, encoded):
            receiveStrip(partID: partID, encoded: encoded)
        case let .done(partID):
            receiveDone(partID: partID)
        }
    }

    private func receivePen(partID: UUID, x: Double?, y: Double?) {
        guard partID == watchedPartID else { return }
        guard let x, let y else {
            partnerPen = nil
            return
        }
        partnerPen = CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
        // The partner draws again, such as after a refused part came back.
        if partnerFinishedPartID == partID {
            partnerFinishedPartID = nil
            recompute()
        }
    }

    private func receiveStrip(partID: UUID, encoded: String) {
        guard partID == watchedPartID || partID == previousPartID, let drawing = Self.decodeStrip(encoded) else {
            return
        }
        rememberLiveStrip(drawing, partID: partID)
        if partID == watchedPartID {
            partnerStrip = drawing
        }
        updateStrip()
    }

    private func receiveDone(partID: UUID) {
        guard partID == watchedPartID, partnerFinishedPartID != partID else { return }
        partnerPen = nil
        partnerFinishedPartID = partID
        partnerFinishedPart = part
        partnerDonePulse += 1
        recompute()
    }

    /// The most a live strip may weigh. A real strip is a few kilobytes.
    private static let maxLiveStripBytes = 2_097_152

    private static func decodeStrip(_ encoded: String) -> PKDrawing? {
        guard encoded.utf8.count <= maxLiveStripBytes * 2,
              let data = Data(base64Encoded: encoded), data.count <= maxLiveStripBytes
        else { return nil }
        return try? PKDrawing(data: data)
    }

    private func rememberLiveStrip(_ drawing: PKDrawing, partID: UUID) {
        liveStrips[partID] = drawing
        liveStripOrder.removeAll { $0 == partID }
        liveStripOrder.append(partID)
        while liveStripOrder.count > Self.keptLiveStrips {
            liveStrips[liveStripOrder.removeFirst()] = nil
        }
    }

    private static let keptLiveStrips = 4

    // MARK: - Watching

    /// Clears what the folded paper showed when the part changes or the partner
    /// leaves, and works out the "finished" line.
    func updateWatching(partnerPartID: UUID?) {
        if watchedPartID != partnerPartID {
            watchedPartID = partnerPartID
            partnerFinishedPartID = nil
            if partnerPen != nil { partnerPen = nil }
            // The strip may have arrived before the phase caught up.
            partnerStrip = partnerPartID.flatMap { liveStrips[$0] }
        }
        let hasFinished = partnerPartID != nil && partnerFinishedPartID == partnerPartID
        if live?.partnerActivity != .drawing, !hasFinished {
            // The partner left. Their pen and strip are stale.
            if partnerPen != nil { partnerPen = nil }
            if partnerStrip != nil { partnerStrip = nil }
        }
        let finishedPart = hasFinished ? part : nil
        if partnerFinishedPart != finishedPart {
            partnerFinishedPart = finishedPart
        }
    }
}
