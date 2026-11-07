import Foundation
import MapKit
import Observation
import UIKit

// The partner: what they are doing, the invite, the live room with the guess map,
// the marks on the pins, and the screen opening and closing.
extension GuessMySpotViewModel {
    func updateContinuation(attention: GameAttention) {
        if case .reveal = phase, live?.partnerActivity == .result {
            partnerResultID = round?.id
        }
        continuation = makeContinuation()
        if state != nil {
            attentionCue.update(attention.including(continuation), isActive: isRunning && isActive)
        }
    }

    func makeContinuation() -> GameContinuation? {
        guard case .reveal(isHeld: false) = phase, let round, let userID = currentUserID else { return nil }
        if let next = state?.currentRound, next.roundNumber > round.roundNumber,
           next.senderUserID != userID, !next.isGuessed {
            return GameContinuation(id: "round \(next.id) sent", status: .sentPhoto)
        }
        if round.guesserUserID == userID, partnerResultID == round.id, live?.partnerActivity == .present {
            return GameContinuation(id: "round \(round.id) partner waiting", status: .waiting)
        }
        return nil
    }

    // MARK: - Lifecycle

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        isStopped = false
        isActive = true
        await reload()
        guard isRunning, !Task.isCancelled else { return }
        loops.beginObserving(
            currentUserID: { [weak self] in self?.currentUserID },
            reload: { [weak self] in await self?.reload() }
        )
        loops.beginTicking(every: tickInterval) { [weak self] in
            guard let self else { return }
            now = dependencies.now()
            recompute()
        }
        if isActive {
            loops.beginHeartbeat()
            startLive()
        }
        await refresh()
    }

    func stop(preservingPresentation: Bool = false) {
        guard isRunning else { return }
        // A reveal watched to its verdict is seen, as leaving it with back.
        if !preservingPresentation, case .reveal = phase, let id = round?.id, settledRevealRoundID == id {
            continueFromReveal()
        }
        isRunning = false
        isStopped = true
        attentionCue.reset()
        loops.cancelFollowing()
        for task in [startTask] {
            task?.cancel()
        }
        startTask = nil
        loops.endHeartbeat()
        stopLive()
        // The draft stays, so a look at "Our guesses" loses nothing. A held reveal
        // stepped past plays on the next visit.
        if !preservingPresentation { deferredReveals = [] }
    }

    func scenePhaseChanged(isActive newValue: Bool) {
        guard isRunning, newValue != isActive else { return }
        isActive = newValue
        if newValue {
            loops.beginHeartbeat()
            startLive()
            recompute()
            loops.refresh { [weak self] in await self?.refresh() }
        } else {
            loops.endHeartbeat()
            stopLive()
        }
    }

    // MARK: - Presence

    var isPartnerInLiveRoom: Bool {
        live.map { $0.partnerActivity != .away } ?? false
    }

    var isPartnerHere: Bool {
        isPartnerInLiveRoom || overview?.presence(for: .guessMySpot)?.partnerPresent == true
    }

    func updatePartnerStatus() {
        var status: GuessMySpotPartnerStatus = isPartnerHere ? .here : .away
        switch live?.partnerActivity {
        case .choosing: status = .picking
        case .watching: status = .guessing
        default: break
        }
        if partnerStatus != status {
            partnerStatus = status
        }
        // The partner's live map belongs to the round they guess while this person
        // waits. It goes when they leave or the round moves on.
        if partnerMapView != nil, status != .guessing || !isWaitingForGuess {
            partnerMapView = nil
        }
        // A completed round's preview must not appear when the partner picks again.
        if let preview = partnerPhotoPreview, isCompletedPreviewRound(preview.roundID) {
            partnerPhotoPreview = nil
        }
        // A partner who left without sending took their photo with them.
        if partnerPhotoPreview != nil, status == .away, phase == .waitingForPhoto {
            partnerPhotoPreview = nil
        }
        let invite = GameInviteState.make(
            lastInviteAt: overview?.presence(for: .guessMySpot)?.lastInviteAt,
            localSentAt: localInviteSentAt,
            partnerIsHere: isPartnerHere,
            now: now
        )
        if self.invite != invite {
            self.invite = invite
        }
    }

    private var isWaitingForGuess: Bool {
        if case .waitingForGuess = phase { return true }
        return false
    }

    // MARK: - Invite

    func sendInvite() async {
        now = dependencies.now()
        updatePartnerStatus()
        guard invite == .available else { return }
        localInviteSentAt = dependencies.now()
        recompute()
        let delivery = await GameInviteDelivery.send(.guessMySpot, through: dependencies.gateway)
        localInviteSentAt = delivery.localSentAt(optimistic: localInviteSentAt)
        if let failure = delivery.failure {
            notice = .couldNotSendInvite(failure)
        }
        recompute()
    }

    // MARK: - Live room

    /// As often as Draw & Guess sends a stroke.
    static let liveMapViewInterval: TimeInterval = 1.0 / 30

    func attach(_ room: WidgetLiveDrawing) {
        room.onPartnerArrived = { [weak self] in
            self?.sendLiveMapView()
            self?.sendLivePreview()
        }
        let channel = GameLiveChannel<GuessMySpotLiveMessage>(connection: room.connection)
        channel.onMessage = { [weak self] message in self?.receive(message) }
        liveChannel = channel
        live = room
    }

    func startLive() {
        guard let live else { return }
        live.start()
        syncLiveRole()
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
        partnerMapView = nil
    }

    /// Tells the partner's phone what this screen is doing.
    func syncLiveRole() {
        guard let live else { return }
        let role: WidgetLivePresence.Role = switch phase {
        case .send: .choosing
        case .guess: .watching
        case .reveal: .result
        default: .present
        }
        live.switchRole(to: role)
    }

    /// The guess map moved. `settled` is the end of a move, which goes out unless the
    /// last frame already sent it, so the sender ends on the same view however the
    /// sends were spaced.
    func guessMapMoved(to rect: MKMapRect, settled: Bool) {
        guessMapRect = rect
        let now = CACurrentMediaTime()
        guard GuessMySpotLiveMapView(rect, satellite: guessMapSatellite) != liveMapViewSent,
              settled || now - liveMapViewSentAt >= Self.liveMapViewInterval
        else { return }
        liveMapViewSentAt = now
        sendLiveMapView()
    }

    func guessMapSatelliteChanged(to satellite: Bool) {
        guard guessMapSatellite != satellite else { return }
        guessMapSatellite = satellite
        sendLiveMapView()
    }

    /// Sends what this person's guess map shows. Only the guesser sends, never the
    /// pin, and never a spot of a photo: the real spot never goes over the relay.
    func sendLiveMapView() {
        guard phase == .guess, let round, let rect = guessMapRect else { return }
        let view = GuessMySpotLiveMapView(rect, satellite: guessMapSatellite)
        liveMapViewSent = view
        liveChannel?.send(.guessMap(roundID: round.id, view: view))
    }

    /// Sends the few pixels of the photo this person is checking, so the partner
    /// sees it coming.
    func sendLivePreview() {
        guard phase == .send, let draft, let jpeg = draft.preview else { return }
        liveChannel?.send(.photoPreview(roundID: draft.roundID, jpeg: jpeg))
    }

    func receive(_ message: GuessMySpotLiveMessage) {
        switch message {
        case let .guessMap(roundID, view):
            receiveGuessMap(roundID: roundID, view: view)
        case let .photoPreview(roundID, jpeg):
            // Kept in any phase: the partner may pick their photo while this person
            // still watches the last reveal.
            guard phase != .send, !isCompletedPreviewRound(roundID),
                  partnerPhotoPreview?.roundID != roundID,
                  let preview = GuessMySpotPhotoPreview(roundID: roundID, jpeg: jpeg)
            else { return }
            partnerPhotoPreview = preview
        case .photoPreviewCleared:
            if phase != .guess {
                partnerPhotoPreview = nil
            }
        }
    }

    private func isCompletedPreviewRound(_ roundID: UUID) -> Bool {
        [state?.currentRound, state?.previousRound].contains { round in
            round?.id == roundID && round?.isGuessed == true
        }
    }

    /// The partner's guess map, shown only while this person waits for that guess.
    private func receiveGuessMap(roundID: UUID, view: GuessMySpotLiveMapView) {
        let rect = view.rect
        guard isWaitingForGuess, roundID == round?.id,
              [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite),
              rect.size.width > 0, rect.size.height > 0
        else { return }
        if partnerMapView != view {
            partnerMapView = view
        }
    }

    /// The partner's preview of the round on screen, while its photo is on its way.
    var roundPhotoPreview: UIImage? {
        guard let preview = partnerPhotoPreview, preview.roundID == round?.id else { return nil }
        return preview.image
    }

    // MARK: - Marks

    func updateStyles() {
        let styles = markImages.coupleStyles(
            participants: participants,
            currentUserID: currentUserID,
            partnerUserID: state?.partnerUserID
        )
        if myStyle != styles.mine {
            myStyle = styles.mine
        }
        if partnerStyle != styles.partner {
            partnerStyle = styles.partner
        }
    }

    /// The style of whoever sent or guessed: this person's or the partner's.
    func style(of userID: UUID?) -> BoardPieceStyle {
        userID == currentUserID ? myStyle : partnerStyle
    }
}
