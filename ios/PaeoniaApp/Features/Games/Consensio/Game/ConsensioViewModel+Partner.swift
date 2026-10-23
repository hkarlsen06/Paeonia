import Foundation
import Observation
import UIKit

// The partner: what they are doing, the invite, the live room with the guess
// marker, the marks on the pins, and the screen opening and closing.
extension ConsensioViewModel {
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
        for task in [startTask, refreshTask, liveSendTask] {
            task?.cancel()
        }
        startTask = nil
        refreshTask = nil
        liveSendTask = nil
        loops.endHeartbeat()
        stopLive()
        // The topic and pin being placed stay, so a look at "What we know" loses
        // nothing. A held reveal stepped past plays on the next visit.
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
        isPartnerInLiveRoom || overview?.presence(for: .consensio)?.partnerPresent == true
    }

    func updatePartnerStatus() {
        var status: ConsensioPartnerStatus = isPartnerHere ? .here : .away
        switch live?.partnerActivity {
        case .choosing: status = .picking
        case .watching: status = .guessing
        case .result: status = .lookingAtResult
        default: break
        }
        if partnerStatus != status {
            partnerStatus = status
        }
        // The partner's live marker belongs to the round they guess while this
        // person waits. It goes when they leave or the round moves on.
        if partnerMarker != nil, status != .guessing || !isWaitingForGuess {
            partnerMarker = nil
            partnerIsTouching = false
        }
        let invite = GameInviteState.make(
            lastInviteAt: overview?.presence(for: .consensio)?.lastInviteAt,
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
            let result = try await dependencies.gateway.sendInvite(.consensio)
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

    func attach(_ room: WidgetLiveDrawing) {
        room.onPartnerArrived = { [weak self] in self?.sendLiveMarker(force: true) }
        let channel = GameLiveChannel<ConsensioLiveMessage>(connection: room.connection)
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
        partnerMarker = nil
    }

    /// Tells the partner's phone what this screen is doing.
    func syncLiveRole() {
        guard let live else { return }
        let role: WidgetLivePresence.Role = switch phase {
        case .choose: .choosing
        case .guess: .watching
        case .reveal: .result
        default: .present
        }
        live.switchRole(to: role)
    }

    /// The most guess messages a second, so a dragging finger never floods the room.
    static let liveSendInterval: Duration = .milliseconds(66)

    /// Sends where this person's guess marker is. Only the guesser sends, and
    /// never a placement: the real spot never goes over the relay.
    func sendLiveMarker(force: Bool = false) {
        guard phase == .guess, let round else { return }
        let elapsed = lastLiveSendAt.map { ContinuousClock.now - $0 } ?? .seconds(1)
        if force || !isTouchingMarker || elapsed >= Self.liveSendInterval {
            liveSendTask?.cancel()
            liveSendTask = nil
            lastLiveSendAt = .now
            liveChannel?.send(ConsensioLiveMessage(roundID: round.id, position: marker, touching: isTouchingMarker))
            return
        }
        // The last position of a quick drag still goes out.
        guard liveSendTask == nil else { return }
        liveSendTask = Task { [weak self, sleep] in
            try? await sleep(Self.liveSendInterval - elapsed)
            guard !Task.isCancelled, let self else { return }
            liveSendTask = nil
            sendLiveMarker(force: true)
        }
    }

    /// The partner's guess marker, shown only while this person waits for that guess.
    func receive(_ message: ConsensioLiveMessage) {
        guard isWaitingForGuess, message.roundID == round?.id else { return }
        if partnerMarker != message.position {
            partnerMarker = message.position
        }
        if partnerIsTouching != message.touching {
            partnerIsTouching = message.touching
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

    /// The style of whoever placed or guessed: this person's or the partner's.
    func style(of userID: UUID?) -> BoardPieceStyle {
        userID == currentUserID ? myStyle : partnerStyle
    }
}
