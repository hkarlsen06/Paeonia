import Foundation
import Observation

/// What the partner is doing in the game, as the screen shows it.
nonisolated enum StoryChainPartnerPresence: Equatable, Sendable {
    /// Not in the game.
    case away
    /// In the game, on a screen with nothing to do for this person.
    case here
    /// Reading the story while this person writes.
    case reading
    /// Writing a line.
    case writing
    /// Picking an opening, or naming a story.
    case choosing
    /// Looking at a finished story.
    case result

    var isHere: Bool {
        self != .away
    }
}

/// The partner's latest live message and when it arrived on this phone.
nonisolated struct StoryChainReceivedMessage: Equatable, Sendable {
    let message: StoryChainLiveMessage
    let receivedAt: Date
}

/// The line a composer is for: a story and the number of the line in it.
nonisolated struct StoryChainWritingKey: Equatable, Sendable {
    let storyID: UUID
    let number: Int
}

// The partner: the heartbeat that says this screen is open, the invite, the live
// room, and the partner's live draft.
extension StoryChainViewModel {
    /// A draft older than this without an update fades out, so a writer who left
    /// without sending leaves no ghost behind.
    static let draftLifetime: TimeInterval = 10

    // MARK: - Presence

    func beginHeartbeat() {
        heartbeatTask?.cancel()
        let gateway = dependencies.gateway
        let interval = heartbeatInterval
        let sleep = sleep
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await gateway.setPresence(.storyChain, isPresent: true)
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
        Task { try? await gateway.setPresence(.storyChain, isPresent: isPresent) }
    }

    /// The live room says what the partner's screen shows. Without it, the
    /// shared overview's heartbeat says whether the partner is in the game.
    func currentPartnerPresence() -> StoryChainPartnerPresence {
        switch live?.partnerActivity {
        case .drawing: .writing
        case .watching: .reading
        case .choosing: .choosing
        case .result: .result
        case .present: .here
        case .away, nil: overviewPresence?.partnerPresent == true ? .here : .away
        }
    }

    // MARK: - Invite

    /// "Tell [Name] you want to play". One invite every 15 minutes.
    func sendInvite() async {
        // The button may have come back since the last tick.
        recompute()
        guard invite == .available else { return }
        localInviteSentAt = dependencies.now()
        recompute()
        do {
            let result = try await dependencies.gateway.sendInvite(.storyChain)
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
        room.onPartnerArrived = { [weak self] in self?.resendDraftLive() }
        let channel = GameLiveChannel<StoryChainLiveMessage>(connection: room.connection)
        channel.onMessage = { [weak self] message in self?.receive(message) }
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
                recompute()
            }
        }
    }

    func stopLive() {
        liveObservationTask?.cancel()
        liveObservationTask = nil
        liveWindowTask?.cancel()
        liveWindowTask = nil
        liveDraftIsDirty = false
        live?.stop()
        // A draft from before the socket closed can't be told from a stale one.
        partnerMessage = nil
        recompute()
    }

    // MARK: - Sending the draft

    /// The line the composer is for, while this person writes and the room is open.
    private var liveKey: StoryChainWritingKey? {
        guard phase == .writing, liveChannel != nil, let story else { return nil }
        let key = StoryChainWritingKey(storyID: story.id, number: nextLineNumber)
        return key == liveSentKey ? nil : key
    }

    /// Sends the whole draft, at most once per `liveSendInterval`. A change inside
    /// the window waits for its end, and only the latest draft goes.
    func sendDraftLive() {
        guard liveKey != nil else { return }
        if liveWindowTask == nil {
            flushDraftLive()
        } else {
            liveDraftIsDirty = true
        }
    }

    /// The partner joined or came back, and may have missed the draft.
    func resendDraftLive() {
        guard liveKey != nil else { return }
        flushDraftLive()
    }

    private func flushDraftLive() {
        guard let key = liveKey else { return }
        liveDraftIsDirty = false
        liveChannel?.send(StoryChainLiveMessage(
            story: key.storyID,
            number: key.number,
            text: draft,
            isLast: isLastLine
        ))
        liveWindowTask?.cancel()
        let interval = liveSendInterval
        let sleep = sleep
        liveWindowTask = Task { [weak self] in
            try? await sleep(interval)
            guard !Task.isCancelled, let self else { return }
            liveWindowTask = nil
            if liveDraftIsDirty {
                flushDraftLive()
            }
        }
    }

    /// Tells the partner's page the line is sent, with its id, so it plays the
    /// arrival before Convex confirms. No draft message follows it.
    func sendLineLive(_ line: StoryChainQueuedLine, number: Int) {
        liveSentKey = StoryChainWritingKey(storyID: line.storyID, number: number)
        liveWindowTask?.cancel()
        liveWindowTask = nil
        liveDraftIsDirty = false
        liveChannel?.send(StoryChainLiveMessage(
            story: line.storyID,
            number: number,
            text: line.text,
            isLast: line.isLast,
            lineID: line.lineID,
            sent: true
        ))
    }

    // MARK: - Receiving

    func receive(_ message: StoryChainLiveMessage) {
        now = dependencies.now()
        partnerMessage = StoryChainReceivedMessage(message: message, receivedAt: now)
        // The line plays in the moment the writer taps Send. When the same line
        // comes from Convex, it is already animated and nothing moves.
        if let lineID = liveSentLine?.lineID, !animatedLineIDs.contains(lineID) {
            beginArrival(of: lineID, isMine: false)
        }
        recompute()
    }

    /// The partner's draft about the line they write now, while it is fresh. Nil
    /// when it is about another story or line, or too old.
    var freshPartnerDraft: StoryChainLiveMessage? {
        guard phase == .waitingForLine, let story, let received = partnerMessage, !received.message.sent,
              received.message.story == story.id,
              received.message.number == story.story.lines.count + 1,
              now.timeIntervalSince(received.receivedAt) < Self.draftLifetime
        else { return nil }
        return received.message
    }

    /// The partner's draft as the page shows it after the last line.
    var partnerGhost: StoryChainGhost? {
        freshPartnerDraft.flatMap { message in
            message.text.isEmpty ? nil : StoryChainGhost(text: message.text, isLast: message.isLast)
        }
    }

    /// The line the partner sent live that Convex has not delivered yet.
    var liveSentLine: StoryChainLiveMessage? {
        guard phase == .waitingForLine, let story, let message = partnerMessage?.message, message.sent,
              let lineID = message.lineID, message.story == story.id,
              message.number == story.story.lines.count + 1,
              !story.story.lines.contains(where: { $0.id == lineID })
        else { return nil }
        return message
    }
}
