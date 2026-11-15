#if targetEnvironment(simulator)
import AVFoundation
import Foundation
@preconcurrency import LiveCommunicationKit

/// Stands in for the system call service on the simulator, where the system ends every call at
/// once because it has no call UI to show. It hands each request straight back to the engine and
/// runs the call's audio session itself. Nothing shows outside the app, so an incoming call rings
/// only inside the app, and only while it is open.
final class SimulatorCallSystem: CallSystem {
    private weak var delegate: (any CallSystemDelegate)?
    private var conversations: Set<UUID> = []
    private var audioConversation: UUID?

    private struct UnknownConversation: Error {}

    func start(delegate: any CallSystemDelegate) {
        self.delegate = delegate
    }

    /// The system activates an outgoing call's audio once the app fulfills the start, as CallKit
    /// does, so the caller hears the ringback.
    func startOutgoing(_ conversationID: UUID, to handle: Handle) {
        conversations.insert(conversationID)
        deliver(.start, for: conversationID, onFulfill: { [weak self] in
            self?.activateAudio(for: conversationID)
        }, onFail: { [weak self] in
            self?.conversations.remove(conversationID)
        })
    }

    func reportIncoming(_ conversationID: UUID, from handle: Handle) {
        conversations.insert(conversationID)
    }

    func reportConnecting(_ conversationID: UUID) {}

    func reportConnected(_ conversationID: UUID) {}

    func reportUpdated(_ conversationID: UUID, hasVideo: Bool) {}

    func reportEnded(_ conversationID: UUID, reason: CallEndReason) {
        endConversation(conversationID)
    }

    func requestJoin(_ conversationID: UUID) throws {
        try request(.join, for: conversationID) { [weak self] in
            self?.activateAudio(for: conversationID)
        }
    }

    func requestEnd(_ conversationID: UUID) throws {
        try request(.end, for: conversationID) { [weak self] in
            self?.endConversation(conversationID)
        }
    }

    func requestMute(_ conversationID: UUID, isMuted: Bool) throws {
        try request(.mute(isMuted), for: conversationID)
    }

    private func request(
        _ action: CallSystemAction,
        for conversationID: UUID,
        onFulfill: @escaping () -> Void = {}
    ) throws {
        guard conversations.contains(conversationID) else { throw UnknownConversation() }
        deliver(action, for: conversationID, onFulfill: onFulfill)
    }

    private func deliver(
        _ action: CallSystemAction,
        for conversationID: UUID,
        onFulfill: @escaping () -> Void = {},
        onFail: @escaping () -> Void = {}
    ) {
        delegate?.handle(CallSystemRequest(
            action: action,
            conversationID: conversationID,
            fulfill: onFulfill,
            fail: onFail
        ))
    }

    /// Runs after the engine's current work, as the system's callback would. Without audio the
    /// engine's activation timer fails the call, as on a phone.
    private func activateAudio(for conversationID: UUID) {
        Task { [weak self] in
            guard let self, conversations.contains(conversationID), audioConversation == nil else { return }
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
                try session.setActive(true)
            } catch {
                return
            }
            audioConversation = conversationID
            delegate?.audioActivated(session)
        }
    }

    private func endConversation(_ conversationID: UUID) {
        conversations.remove(conversationID)
        guard audioConversation == conversationID else { return }
        audioConversation = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        delegate?.audioDeactivated(session)
    }
}
#endif
