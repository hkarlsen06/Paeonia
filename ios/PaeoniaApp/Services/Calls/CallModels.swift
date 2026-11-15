import Foundation

/// The call with the partner, as the app shows it. `CallCenter.session` holds the live one.
/// `docs/calling-plan.md` has the rules.
nonisolated struct CallSession: Equatable, Identifiable, Sendable {
    /// The conversation UUID. The same id names the call in Convex, LiveCommunicationKit and the relay.
    let id: UUID
    let direction: CallDirection
    var phase: CallPhase
    var isMuted = false
    var audioRoute: CallAudioRoute = .receiver
    var isCameraOn = false
    var isPartnerCameraOn = false
    var isUsingFrontCamera = true

    /// A voice call on the earpiece, which the person holds to their ear, so the screen turns off
    /// and their cheek cannot press anything. An incoming ring is the system's to show.
    var usesProximitySensor: Bool {
        guard audioRoute == .receiver, !isCameraOn, !isPartnerCameraOn else { return false }
        return switch phase {
        case .ringing: direction == .outgoing
        case .connecting, .active, .reconnecting: true
        case .ended: false
        }
    }
}

nonisolated enum CallDirection: Equatable, Sendable {
    case outgoing
    case incoming
}

nonisolated enum CallPhase: Equatable, Sendable {
    /// An outgoing call waits for the partner. An incoming one rings on the system call UI, and the app shows nothing.
    case ringing
    /// Answered, and the phones are connecting.
    case connecting
    /// Talking since `since`, which the call timer counts from.
    case active(since: Date)
    /// The connection dropped and the phones are trying again. `since` is when the call started,
    /// so the timer keeps counting.
    case reconnecting(since: Date)
    /// The call is over. The call screen shows why for a moment, then `CallCenter` clears the session.
    case ended(CallEndReason)
}

nonisolated enum CallEndReason: Equatable, Sendable {
    /// Someone ended a call that was going.
    case hungUp
    /// The partner did not answer, declined, or the ring ran out.
    case noAnswer
    /// You did not answer an incoming call before it stopped ringing.
    case missed
    /// Another of your devices answered or declined.
    case answeredElsewhere
    /// The couple already has a call going.
    case busy
    case failed(CallFailure)
}

nonisolated enum CallFailure: Equatable, Sendable {
    /// The phone has no connection (`PaeoniaFailure.offline`).
    case offline
    /// The phones could not reach each other, or the connection did not come back.
    case couldNotConnect
    /// Paeonia may not use the microphone.
    case microphoneDenied
    /// A call back from Recents or Siri to someone who is no longer the partner.
    case notPartner
    /// Any other error. The copy says something went wrong and to try again.
    case other
}

nonisolated enum CallAudioRoute: Equatable, Sendable {
    case receiver
    case speaker
    /// AirPods, a headset or a car. `name` is the route's name from the system.
    case external(name: String)
}

nonisolated enum CallVideoSource: Equatable, Sendable {
    case local
    case partner
}

/// How the call shows inside the app: the full call screen, or the floating bubble over the other screens.
nonisolated enum CallPresentation: Equatable, Sendable {
    case full
    case bubble
}
