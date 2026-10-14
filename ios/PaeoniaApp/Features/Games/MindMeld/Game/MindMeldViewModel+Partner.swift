import Foundation
import Observation

// The partner: the heartbeat that says this screen is open, what the partner is
// doing, the invite, and the live room with the typing message.
extension MindMeldViewModel {
    // MARK: - Presence

    func beginHeartbeat() {
        heartbeatTask?.cancel()
        let gateway = dependencies.gateway
        let interval = heartbeatInterval
        let sleep = sleep
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await gateway.setPresence(.mindMeld, isPresent: true)
                try? await sleep(interval)
            }
        }
    }

    func endHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        sendPresence(false)
    }

    func sendPresence(_ isPresent: Bool) {
        let gateway = dependencies.gateway
        Task { try? await gateway.setPresence(.mindMeld, isPresent: isPresent) }
    }

    /// The partner is in the live room.
    var isPartnerInLiveRoom: Bool {
        live.map { $0.partnerActivity != .away } ?? false
    }

    /// The partner has the game open: in the live room, or with a fresh heartbeat.
    var isPartnerHere: Bool {
        isPartnerInLiveRoom
            || GamePresence.isFresh(overview?.presence(for: .mindMeld)?.partnerLastSeenAt, now: now)
    }

    /// Works out the partner's status and the invite. A locked word beats typing,
    /// and typing beats being here.
    func updatePartnerStatus() {
        let isHere = isPartnerHere
        var status: MindMeldPartnerStatus = isHere ? .here : .away
        if let open = openRound {
            if open.partnerLocked {
                status = .locked
            } else if isPartnerInLiveRoom, partnerTypingRound == open.roundNumber {
                status = .typing
            }
        }
        if partnerStatus != status {
            partnerStatus = status
        }
        let invite = GameInviteState.make(
            lastInviteAt: overview?.presence(for: .mindMeld)?.lastInviteAt,
            localSentAt: localInviteSentAt,
            partnerIsHere: isHere,
            now: now
        )
        if self.invite != invite {
            self.invite = invite
        }
    }

    // MARK: - Invite

    /// "Tell [Name] you want to play". One invite every 15 minutes.
    func sendInvite() async {
        // The button may have come back since the last tick.
        now = dependencies.now()
        updatePartnerStatus()
        guard invite == .available else { return }
        localInviteSentAt = dependencies.now()
        recompute()
        do {
            let result = try await dependencies.gateway.sendInvite(.mindMeld)
            localInviteSentAt = result.sentAt
        } catch let error as PaeoniaConvexError {
            if case .server(code: "53300", message: _) = error {
                // The server already counted an invite in the last 15 minutes.
                return
            }
            localInviteSentAt = nil
            notice = .couldNotSendInvite
        } catch {
            localInviteSentAt = nil
            notice = .couldNotSendInvite
        }
        recompute()
    }

    // MARK: - Live room

    func attach(_ room: WidgetLiveDrawing) {
        room.onPartnerArrived = { [weak self] in self?.resendTyping() }
        let channel = GameLiveChannel<MindMeldLiveMessage>(connection: room.connection)
        channel.onMessage = { [weak self] message in self?.receiveTyping(message) }
        liveChannel = channel
        live = room
    }

    func startLive() {
        guard let live else { return }
        live.start()
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
    }

    // MARK: - Typing

    /// How long after the last change the person still counts as typing.
    static let typingIdleDelay: Duration = .seconds(3)
    /// A person who keeps typing repeats the message this often, so the partner's
    /// phone does not time it out.
    static let typingRepeatDelay: Duration = .seconds(2)

    /// Tells the partner whether this person is typing: the field is not empty and
    /// changed in the last 3 seconds.
    func updateTyping() {
        typingIdleTask?.cancel()
        typingIdleTask = nil
        guard phase == .write, !MindMeldWord.normalized(draft).isEmpty else {
            sendTyping(false)
            return
        }
        sendTyping(true)
        typingIdleTask = Task { [weak self, sleep] in
            try? await sleep(Self.typingIdleDelay)
            guard !Task.isCancelled else { return }
            self?.sendTyping(false)
        }
    }

    /// Sends the typing state when it changed, when `force` is set, or when
    /// "typing" is due again.
    func sendTyping(_ isTyping: Bool, force: Bool = false) {
        let isRepeatDue = lastTypingSentAt.map { ContinuousClock.now - $0 >= Self.typingRepeatDelay } ?? true
        guard force || isTyping != sentTyping || (isTyping && isRepeatDue) else { return }
        sentTyping = isTyping
        lastTypingSentAt = .now
        liveChannel?.send(MindMeldLiveMessage(roundNumber: openRound?.roundNumber ?? 1, isTyping: isTyping))
    }

    /// The partner arrived and may have missed the last message.
    func resendTyping() {
        sendTyping(sentTyping, force: true)
    }

    /// The partner says whether they are typing. It shows only while the open
    /// round is the one they are typing in.
    func receiveTyping(_ message: MindMeldLiveMessage) {
        if message.isTyping {
            partnerTypingRound = message.roundNumber
            partnerTypingTask?.cancel()
            partnerTypingTask = Task { [weak self, sleep, timeout = typingTimeout] in
                try? await sleep(timeout)
                guard !Task.isCancelled, let self else { return }
                partnerTypingRound = nil
                updatePartnerStatus()
            }
        } else if partnerTypingRound == message.roundNumber {
            partnerTypingTask?.cancel()
            partnerTypingTask = nil
            partnerTypingRound = nil
        }
        updatePartnerStatus()
    }
}
