import Foundation

/// The call with the partner, as the app shows it. `CallCenter.session` holds the live one.
/// `docs/calling-plan.md` has the rules.
nonisolated struct CallSession: Equatable, Identifiable, Sendable {
    /// The conversation UUID. The same id names the call in Convex, LiveCommunicationKit and the relay.
    /// It changes once, when `start_call` answers the partner's ringing call instead.
    var id: UUID
    let direction: CallDirection
    var phase: CallPhase
    var isMuted = false
    var audioRoute: CallAudioRoute = .receiver
    var isCameraOn = false
    /// The partner's camera as their phone reports it (`CallCameraState`).
    var partnerCamera = CallCameraState.off
    /// The width of the partner's video over its height, as their phone is held. Nil until the
    /// first frame arrives. The bubble takes this shape, so it shows the whole picture.
    var partnerVideoAspectRatio: CGFloat?
    /// The width of this person's own video over its height, as the phone is held. Nil until the
    /// camera's first frame. The viewfinder takes this shape, so it shows what the partner sees.
    var localVideoAspectRatio: CGFloat?
    var isUsingFrontCamera = true
    /// This person shares their screen (`CallScreenCapture`).
    var isSharingScreen = false
    var isPartnerSharingScreen = false
    /// The width of the partner's shared screen over its height. Nil until its first frame arrives.
    var partnerScreenAspectRatio: CGFloat?
    /// Set while the call's connection is weak, and says whose end is weak. Nil while it is fine.
    var weakConnection: CallWeakSide?
    /// The partner's camera is on, but no new frame has arrived for a moment, so the last one would
    /// stand still. The screens show it blurred instead.
    var isPartnerVideoStalled = false
    /// Why the call screen offers to turn this person's camera off, or nil when it does not.
    var cameraOffSuggestion: CallCameraOffSuggestion?
    /// The call was answered before the person said whether Paeonia may use the microphone, so
    /// the partner cannot hear them until they open the app and allow it.
    var isWaitingForMicrophone = false
    /// The partner's call rings inside the app, as the ring pill or the full call screen, because
    /// Paeonia was open on screen when it came in. It stays set when that ring ends unanswered, so
    /// the ring says why where it rang. Answering it, or handing it to the system, clears it.
    var ringsInApp = false

    /// The partner's video has a window: their camera sends, or iOS paused it for a moment.
    var isPartnerCameraOn: Bool {
        partnerCamera != .off
    }

    /// A voice call on the earpiece, which the person holds to their ear, so the screen turns off
    /// and their cheek cannot press anything. An incoming ring is not held to the ear.
    var usesProximitySensor: Bool {
        guard audioRoute == .receiver, !isCameraOn, !isPartnerCameraOn, !isSharingScreen, !isPartnerSharingScreen
        else { return false }
        return switch phase {
        case .ringing: direction == .outgoing
        case .connecting, .active, .reconnecting: true
        case .ended: false
        }
    }
}

/// The back camera's zoom, counted the way the Camera app counts it, where 1 is the main lens and
/// 0.5 the ultra wide.
nonisolated struct CallCameraZoom: Equatable, Sendable {
    let range: ClosedRange<Double>
    var factor: Double
}

nonisolated enum CallDirection: Equatable, Sendable {
    case outgoing
    case incoming
}

nonisolated enum CallPhase: Equatable, Sendable {
    /// An outgoing call waits for the partner. An incoming one rings on the system call UI, or
    /// inside the app while it is open (`CallSession.ringsInApp`).
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
    /// The partner's shared screen.
    case partnerScreen
}

/// The partner's camera, as their phone reports it over the relay.
nonisolated enum CallCameraState: Equatable, Sendable {
    case off
    case on
    /// The camera is on, but iOS stopped it for now, such as when the partner left the app without
    /// Picture in Picture or another app took the camera. It sends again by itself.
    case paused
}

/// Whose end of the call has the weak connection.
nonisolated enum CallWeakSide: Equatable, Sendable {
    case mine
    case partners
}

/// Why the call screen offers to turn this person's camera off.
nonisolated enum CallCameraOffSuggestion: Equatable, Sendable {
    /// The battery is low and the phone is not charging.
    case lowBattery
    /// The phone is hot, and iOS will slow it down.
    case hot
}
