import Foundation
import MapKit
import Observation
import UIKit

// The partner: what they are doing, the invite, the live room with the guess map,
// the marks on the pins, and the screen opening and closing.
extension GuessMySpotViewModel {
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

    func stop() {
        guard isRunning else { return }
        // A reveal watched to its verdict is seen, as leaving it with back.
        if case .reveal = phase, let id = round?.id, settledRevealRoundID == id {
            continueFromReveal()
        }
        isRunning = false
        isStopped = true
        attentionCue.reset()
        loops.cancelFollowing()
        for task in [startTask, refreshTask] {
            task?.cancel()
        }
        startTask = nil
        refreshTask = nil
        loops.endHeartbeat()
        stopLive()
        // The draft stays, so a look at "Our guesses" loses nothing. A held reveal
        // stepped past plays on the next visit.
        deferredReveals = []
    }

    func scenePhaseChanged(isActive newValue: Bool) {
        guard isRunning, newValue != isActive else { return }
        isActive = newValue
        if newValue {
            loops.beginHeartbeat()
            startLive()
            recompute()
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in await self?.refresh() }
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
        do {
            let result = try await dependencies.gateway.sendInvite(.guessMySpot)
            localInviteSentAt = result.sentAt
        } catch let error as PaeoniaConvexError {
            if case .server(code: "53300", message: _) = error {
                // The server already counted an invite in the last 15 minutes.
                return
            }
            localInviteSentAt = nil
            notice = .couldNotSendInvite(PaeoniaFailure(error))
        } catch {
            localInviteSentAt = nil
            notice = .couldNotSendInvite(PaeoniaFailure(error))
        }
        recompute()
    }

    // MARK: - Live room

    /// As often as Draw & Guess sends a stroke.
    static let liveMapViewInterval: TimeInterval = 1.0 / 30

    func attach(_ room: WidgetLiveDrawing) {
        room.onPartnerArrived = { [weak self] in self?.sendLiveMapView() }
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
                updatePartnerStatus()
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
        liveChannel?.send(GuessMySpotLiveMessage(roundID: round.id, view: view))
    }

    /// The partner's guess map, shown only while this person waits for that guess.
    func receive(_ message: GuessMySpotLiveMessage) {
        let rect = message.view.rect
        guard isWaitingForGuess, message.roundID == round?.id,
              [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite),
              rect.size.width > 0, rect.size.height > 0
        else { return }
        if partnerMapView != message.view {
            partnerMapView = message.view
        }
    }

    // MARK: - Marks

    /// The drawn marks as template images, by owner, rendered once per update.
    func renderedMarks(
        _ marks: RemoteBoardGameMarks?,
        userID: UUID,
        partnerID: UUID?
    ) async -> [UUID: (key: String, image: UIImage)] {
        var images: [UUID: (key: String, image: UIImage)] = [:]
        let owners: [(UUID?, RemoteBoardGameMark?)] = [(userID, marks?.mine), (partnerID, marks?.partner)]
        for case let (owner?, mark?) in owners {
            let key = "\(owner.uuidString):\(mark.updatedAt.timeIntervalSince1970)"
            if let kept = markImages[owner], kept.key == key {
                images[owner] = kept
                continue
            }
            guard let data = BoardMarkRenderer.data(fromBase64: mark.drawing),
                  let image = await BoardMarkRenderer.image(from: data, cacheKey: key)
            else { continue }
            images[owner] = (key, image)
        }
        return images
    }

    func updateStyles() {
        let mine = BoardPieceStyle(
            color: .boardGameMine,
            mark: currentUserID.flatMap { markImages[$0]?.image },
            initial: BoardPieceStyle.initial(of: participants.currentName)
        )
        let theirs = BoardPieceStyle(
            color: .boardGamePartner,
            mark: state?.partnerUserID.flatMap { markImages[$0]?.image },
            initial: BoardPieceStyle.initial(of: participants.partnerName)
        )
        if myStyle != mine {
            myStyle = mine
        }
        if partnerStyle != theirs {
            partnerStyle = theirs
        }
    }

    /// The style of whoever sent or guessed: this person's or the partner's.
    func style(of userID: UUID?) -> BoardPieceStyle {
        userID == currentUserID ? myStyle : partnerStyle
    }
}
