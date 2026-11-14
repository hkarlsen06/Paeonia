import AVFoundation
import Foundation
@preconcurrency import LiveCommunicationKit

/// The phone's call service, as the call engine sees it. `LiveCommunicationCallSystem` is the real
/// one. The simulator has no call UI, so it uses `SimulatorCallSystem` instead.
@MainActor
protocol CallSystem: AnyObject {
    /// Connects to the system at launch. The system keeps a weak reference to the delegate.
    func start(delegate: any CallSystemDelegate)

    /// Asks the system to place a call. It hands the call back as a `.start` request.
    func startOutgoing(_ conversationID: UUID, to handle: Handle) async throws
    /// Rings for the partner's call. Throws when the system will not ring, such as under a Focus.
    func reportIncoming(_ conversationID: UUID, from handle: Handle) async throws
    func reportConnecting(_ conversationID: UUID)
    func reportConnected(_ conversationID: UUID)
    func reportUpdated(_ conversationID: UUID, hasVideo: Bool)
    func reportEnded(_ conversationID: UUID, reason: CallEndReason)
    /// The requests below come back as requests to the delegate. They throw when the system has
    /// no such call.
    func requestJoin(_ conversationID: UUID) async throws
    func requestEnd(_ conversationID: UUID) async throws
    func requestMute(_ conversationID: UUID, isMuted: Bool) async throws
}

/// What the system asks of the call engine.
@MainActor
protocol CallSystemDelegate: AnyObject {
    /// Every request ends in `fulfill` or `fail`, or the system's call UI gets stuck.
    func handle(_ request: CallSystemRequest)
    func handleTimeout(_ request: CallSystemRequest)
    /// The system activated the call's audio. WebRTC's audio starts only now.
    func audioActivated(_ audioSession: AVAudioSession)
    func audioDeactivated(_ audioSession: AVAudioSession)
    /// The system dropped every call, such as after its call service restarted.
    func systemReset()
}

nonisolated enum CallSystemAction: Equatable, Sendable {
    case start
    case join
    case end
    case mute(Bool)
}

/// One thing the system asks the engine to do to a call.
struct CallSystemRequest {
    let action: CallSystemAction
    let conversationID: UUID
    let fulfill: () -> Void
    let fail: () -> Void
}
