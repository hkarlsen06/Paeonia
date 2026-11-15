import Foundation

/// Something that happened to the call. `CallMachine.reduce` turns it into the next phase and the
/// work the engine does next.
nonisolated enum CallEvent: Equatable, Sendable {
    /// `start_call` returned. `callID` is the call the server keeps, which is the partner's call
    /// when theirs was ringing (`answeredIncoming`).
    case registered(callID: UUID, answeredIncoming: Bool)
    /// This phone answered the incoming call and the server accepted it.
    case answered
    /// What `calls:get_live_call` returned. Nil when the couple has no live call.
    case liveCall(LiveCall?)
    /// The phones reached each other, for the first time or again.
    case connected
    /// The connection between the phones dropped.
    case connectionLost
    /// The system activated the call's audio (`conversationManager(_:didActivate:)`).
    case audioActivated
    /// The system deactivated it (`conversationManager(_:didDeactivate:)`).
    case audioDeactivated
    /// The person ended or declined the call on this phone.
    case hangUp
    /// The call ended somewhere the server already knows about, such as a busy line or an answer
    /// that came too late.
    case ended(CallEndReason)
    /// Something failed on this phone.
    case failed(CallFailure)
    /// `start_call` failed without an answer from the server, such as a timeout. The server may
    /// have started the call anyway.
    case startUnconfirmed(CallFailure)
    case timerFired(CallTimer)
}

nonisolated enum CallTimer: Hashable, Sendable, CaseIterable {
    /// The ring ran out. A fallback for when `get_live_call` cannot say so.
    case ring
    /// The phones did not reach each other after the answer.
    case connect
    /// The connection did not come back.
    case reconnect
    /// The system did not activate the audio after an incoming call was answered or an
    /// outgoing one connected.
    case audioActivation
}

/// What ending the call asks of the server.
nonisolated enum CallServerEnd: Equatable, Sendable {
    case decline
    case end
}

/// Work the engine does after a transition.
nonisolated enum CallEffect: Equatable, Sendable {
    case startTimer(CallTimer, fireAt: Date)
    case cancelTimer(CallTimer)
    /// Fetch the network servers, join the relay and open the peer connection.
    case connectMedia
    /// Reconnect the relay and restart the connection between the phones.
    case restartConnection
    /// The call is over. Tear everything down and tell the system. `server` says what to tell the
    /// server, if anything.
    case finish(CallEndReason, server: CallServerEnd?)
    /// Loop `CallSound.ringback`, or stop it.
    case ringback(isOn: Bool)
    case playConnectedSound
}

/// One call's phase and the facts its transitions depend on. Pure, so the rules in
/// `docs/calling-plan.md` ("Call states") are testable without a phone.
nonisolated struct CallMachine: Equatable, Sendable {
    static let connectTimeout: TimeInterval = 30
    static let reconnectTimeout: TimeInterval = 30
    static let audioActivationTimeout: TimeInterval = 5

    let direction: CallDirection
    /// This install's id (`p_device_id`), to tell an answer here from one on another device.
    let deviceID: UUID
    /// The call the server and the relay know. It changes once, when `start_call` answers the
    /// partner's ringing call instead.
    private(set) var callID: UUID
    private(set) var phase: CallPhase = .ringing
    /// The server has the call, so ending it here must tell the server.
    private(set) var isRegistered: Bool
    /// The server's row for the call has existed, so a missing row now means the call ended.
    private(set) var hasSeenLiveCall: Bool
    private(set) var hasAudio = false
    /// The call connected for the first time and its sound has not played yet, because it plays
    /// only in the audio the system activated.
    private var isConnectedSoundDue = false

    /// An outgoing call, before `start_call` returns.
    static func outgoing(
        callID: UUID,
        deviceID: UUID,
        ringDeadline: Date
    ) -> (CallMachine, [CallEffect]) {
        let machine = CallMachine(
            direction: .outgoing,
            deviceID: deviceID,
            callID: callID,
            isRegistered: false,
            hasSeenLiveCall: false
        )
        return (machine, [.startTimer(.ring, fireAt: ringDeadline)])
    }

    /// An incoming call. The server sends the push and the live row only after the call exists.
    static func incoming(
        callID: UUID,
        deviceID: UUID,
        ringDeadline: Date
    ) -> (CallMachine, [CallEffect]) {
        let machine = CallMachine(
            direction: .incoming,
            deviceID: deviceID,
            callID: callID,
            isRegistered: true,
            hasSeenLiveCall: true
        )
        return (machine, [.startTimer(.ring, fireAt: ringDeadline)])
    }

    /// The caller hears the ringback while the partner's phone rings, once the system has
    /// activated the call's audio. Playing before that would activate the audio session itself.
    var isRingingBack: Bool {
        direction == .outgoing && phase == .ringing && hasAudio
    }

    mutating func reduce(_ event: CallEvent, now: Date) -> [CallEffect] {
        if case .ended = phase {
            return []
        }
        let wasRingingBack = isRingingBack
        let effects = transition(event, now: now)
        return audioEffects(wasRingingBack: wasRingingBack) + effects
    }

    /// The audio goes first, so the ringback stops before the work that follows a ring.
    private mutating func audioEffects(wasRingingBack: Bool) -> [CallEffect] {
        var effects: [CallEffect] = []
        if isRingingBack != wasRingingBack {
            effects.append(.ringback(isOn: isRingingBack))
        }
        if isConnectedSoundDue, case .active = phase {
            if hasAudio {
                isConnectedSoundDue = false
                effects.append(.playConnectedSound)
            }
        } else {
            // Too late once the call has dropped or ended. A reconnect plays nothing.
            isConnectedSoundDue = false
        }
        return effects
    }

    // swiftlint:disable:next cyclomatic_complexity
    private mutating func transition(_ event: CallEvent, now: Date) -> [CallEffect] {
        switch event {
        case let .registered(callID, answeredIncoming):
            return register(callID: callID, answeredIncoming: answeredIncoming, now: now)
        case .answered:
            guard phase == .ringing else { return [] }
            return beginConnecting(now: now) + audioTimer(now: now)
        case let .liveCall(row):
            return observe(row, now: now)
        case .connected:
            return connect(now: now)
        case .connectionLost:
            return loseConnection(now: now)
        case .audioActivated:
            hasAudio = true
            return [.cancelTimer(.audioActivation)]
        case .audioDeactivated:
            hasAudio = false
            return []
        case .hangUp:
            return finish(.hungUp, server: serverEnd)
        case let .ended(reason):
            return finish(reason, server: nil)
        case let .failed(failure):
            return finish(.failed(failure), server: serverEnd)
        case let .startUnconfirmed(failure):
            // Ending a call the server never started does nothing, and it stops the partner's
            // phone ringing when the server did start it.
            return finish(.failed(failure), server: .end)
        case let .timerFired(timer):
            return fire(timer)
        }
    }

    private mutating func connect(now: Date) -> [CallEffect] {
        switch phase {
        case .connecting:
            phase = .active(since: now)
            isConnectedSoundDue = true
            // The system has activated an outgoing call's audio by the time it connects.
            return [.cancelTimer(.connect)] + (direction == .outgoing ? audioTimer(now: now) : [])
        case let .reconnecting(since):
            phase = .active(since: since)
            return [.cancelTimer(.reconnect)]
        default:
            return []
        }
    }

    private mutating func loseConnection(now: Date) -> [CallEffect] {
        switch phase {
        case let .active(since):
            phase = .reconnecting(since: since)
            return [.startTimer(.reconnect, fireAt: now + Self.reconnectTimeout), .restartConnection]
        case .connecting:
            return [.restartConnection]
        default:
            return []
        }
    }

    private mutating func register(callID: UUID, answeredIncoming: Bool, now: Date) -> [CallEffect] {
        guard !isRegistered else { return [] }
        isRegistered = true
        self.callID = callID
        guard answeredIncoming else { return [] }
        hasSeenLiveCall = true
        return beginConnecting(now: now)
    }

    private mutating func observe(_ row: LiveCall?, now: Date) -> [CallEffect] {
        guard let row, row.callID == callID else {
            return rowWentAway()
        }
        hasSeenLiveCall = true
        guard row.state == .active, phase == .ringing else { return [] }
        switch direction {
        case .outgoing:
            return beginConnecting(now: now)
        case .incoming:
            // This phone's own answer moves the phase through `.answered`.
            guard row.answeredDeviceID != deviceID else { return [] }
            return finish(.answeredElsewhere, server: nil)
        }
    }

    /// The server deletes the row whenever a call ends, however it ended.
    private mutating func rowWentAway() -> [CallEffect] {
        guard hasSeenLiveCall else { return [] }
        let reason: CallEndReason = switch (phase, direction) {
        case (.ringing, .outgoing): .noAnswer
        case (.ringing, .incoming): .missed
        default: .hungUp
        }
        return finish(reason, server: nil)
    }

    private mutating func fire(_ timer: CallTimer) -> [CallEffect] {
        switch (timer, phase) {
        case (.ring, .ringing):
            return ringRanOut()
        case (.connect, .connecting), (.reconnect, .reconnecting):
            return finish(.failed(.couldNotConnect), server: serverEnd)
        case (.audioActivation, _) where !hasAudio:
            return finish(.failed(.other), server: serverEnd)
        default:
            return []
        }
    }

    /// A caller cancels on the server so the partner's phone stops too. The server ends an
    /// unanswered incoming call on its own.
    private mutating func ringRanOut() -> [CallEffect] {
        switch direction {
        case .outgoing:
            finish(.noAnswer, server: isRegistered ? .end : nil)
        case .incoming:
            finish(.missed, server: nil)
        }
    }

    private mutating func beginConnecting(now: Date) -> [CallEffect] {
        phase = .connecting
        return [
            .cancelTimer(.ring),
            .startTimer(.connect, fireAt: now + Self.connectTimeout),
            .connectMedia,
        ]
    }

    private func audioTimer(now: Date) -> [CallEffect] {
        hasAudio ? [] : [.startTimer(.audioActivation, fireAt: now + Self.audioActivationTimeout)]
    }

    private mutating func finish(_ reason: CallEndReason, server: CallServerEnd?) -> [CallEffect] {
        phase = .ended(reason)
        return [.finish(reason, server: server)]
    }

    /// Declining stops an incoming ring. Everything else that the server knows about ends.
    private var serverEnd: CallServerEnd? {
        guard isRegistered else { return nil }
        return direction == .incoming && phase == .ringing ? .decline : .end
    }
}
