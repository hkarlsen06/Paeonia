import AVFoundation
import Foundation
@preconcurrency import LiveCommunicationKit
import UIKit

/// The system call UI (LiveCommunicationKit): the Lock Screen, the Dynamic Island and Recents.
final class LiveCommunicationCallSystem: CallSystem {
    private(set) weak var delegate: (any CallSystemDelegate)?
    /// LiveCommunicationKit's manager is safe to call from any thread, but is not marked
    /// `Sendable`, and its async methods leave the main actor.
    nonisolated(unsafe) private let manager: ConversationManager
    private let managerDelegate = ConversationDelegate()

    init() {
        manager = ConversationManager(configuration: ConversationManager.Configuration(
            ringtoneName: CallSound.ring.fileName,
            iconTemplateImageData: Self.iconTemplate(),
            maximumConversationGroups: 1,
            maximumConversationsPerConversationGroup: 1,
            includesConversationInRecents: true,
            supportsVideo: true,
            supportedHandleTypes: [.generic]
        ))
    }

    /// The Paeonia mark on the system call screen's button that opens the app. The system uses
    /// only the alpha, on a square of 40 points.
    private static func iconTemplate() -> Data? {
        let mark = UIImage(resource: .paeoniaMark)
        let side: CGFloat = 120
        let width = side * 0.9
        let height = width * mark.size.height / mark.size.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { _ in
            mark.draw(in: CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
        }
    }

    func start(delegate: any CallSystemDelegate) {
        self.delegate = delegate
        managerDelegate.system = self
        manager.delegate = managerDelegate
    }

    func startOutgoing(_ conversationID: UUID, to handle: Handle) async throws {
        try await manager.perform([
            StartConversationAction(conversationUUID: conversationID, handles: [handle], isVideo: false),
        ])
    }

    func reportIncoming(_ conversationID: UUID, from handle: Handle) async throws {
        try await manager.reportNewIncomingConversation(
            uuid: conversationID,
            update: Conversation.Update(members: [handle], capabilities: [])
        )
    }

    func reportConnecting(_ conversationID: UUID) {
        report(.conversationStartedConnecting(.now), for: conversationID)
    }

    func reportConnected(_ conversationID: UUID) {
        report(.conversationConnected(.now), for: conversationID)
    }

    /// Says whether the call shows video, and never allows pausing or merging.
    func reportUpdated(_ conversationID: UUID, hasVideo: Bool) {
        report(.conversationUpdated(Conversation.Update(capabilities: hasVideo ? [.video] : [])), for: conversationID)
    }

    func reportEnded(_ conversationID: UUID, reason: CallEndReason) {
        guard reason != .noAnswer else {
            // iOS shows its own "unavailable" sheet over the app for an outgoing call that the
            // other side ends before it connects, whatever the reason, so the caller ends it here.
            Task { try? await requestEnd(conversationID) }
            return
        }
        report(.conversationEnded(.now, Self.systemReason(reason)), for: conversationID)
    }

    func requestJoin(_ conversationID: UUID) async throws {
        try await manager.perform([JoinConversationAction(conversationUUID: conversationID)])
    }

    func requestEnd(_ conversationID: UUID) async throws {
        try await manager.perform([EndConversationAction(conversationUUID: conversationID)])
    }

    func requestMute(_ conversationID: UUID, isMuted: Bool) async throws {
        try await manager.perform([MuteConversationAction(conversationUUID: conversationID, isMuted: isMuted)])
    }

    private func report(_ event: Conversation.Event, for conversationID: UUID) {
        guard let conversation = manager.conversations.first(where: { $0.uuid == conversationID }) else { return }
        manager.reportConversationEvent(event, for: conversation)
    }

    private static func systemReason(_ reason: CallEndReason) -> Conversation.EndedReason {
        switch reason {
        case .hungUp, .noAnswer:
            .remoteEnded
        case .missed:
            .unanswered
        case .answeredElsewhere:
            .joinedElsewhere
        case .busy, .failed:
            .failed
        }
    }

    // MARK: The manager's callbacks

    fileprivate func perform(_ action: ConversationAction) {
        guard let request = Self.request(for: action) else {
            // Paeonia calls cannot pause, merge, play tones or translate.
            action.fail()
            return
        }
        delegate?.handle(request)
    }

    fileprivate func timedOut(_ action: ConversationAction) {
        if let request = Self.request(for: action) {
            delegate?.handleTimeout(request)
        }
    }

    private static func request(for action: ConversationAction) -> CallSystemRequest? {
        let kind: CallSystemAction
        let fulfill: () -> Void
        switch action {
        case let action as StartConversationAction:
            kind = .start
            fulfill = { action.fulfill(dateStarted: .now) }
        case let action as JoinConversationAction:
            kind = .join
            fulfill = { action.fulfill(dateConnected: .now) }
        case let action as EndConversationAction:
            kind = .end
            fulfill = { action.fulfill(dateEnded: .now) }
        case let action as MuteConversationAction:
            kind = .mute(action.isMuted)
            fulfill = { action.fulfill() }
        default:
            return nil
        }
        return CallSystemRequest(action: kind, conversationID: action.conversationUUID, fulfill: fulfill) {
            action.fail()
        }
    }
}

/// Receives LiveCommunicationKit's callbacks, which may arrive on any thread, and hands each to
/// the call system on the main thread in the order they came.
private nonisolated final class ConversationDelegate: ConversationManagerDelegate, @unchecked Sendable {
    /// Set once at launch. Read on the main thread only.
    nonisolated(unsafe) weak var system: LiveCommunicationCallSystem?

    func conversationManager(_ manager: ConversationManager, conversationChanged conversation: Conversation) {}

    func conversationManagerDidBegin(_ manager: ConversationManager) {}

    func conversationManagerDidReset(_ manager: ConversationManager) {
        onMain { $0.delegate?.systemReset() }
    }

    func conversationManager(_ manager: ConversationManager, perform action: ConversationAction) {
        nonisolated(unsafe) let action = action
        onMain { $0.perform(action) }
    }

    func conversationManager(_ manager: ConversationManager, timedOutPerforming action: ConversationAction) {
        nonisolated(unsafe) let action = action
        onMain { $0.timedOut(action) }
    }

    func conversationManager(_ manager: ConversationManager, didActivate audioSession: AVAudioSession) {
        onMain { $0.delegate?.audioActivated(audioSession) }
    }

    func conversationManager(_ manager: ConversationManager, didDeactivate audioSession: AVAudioSession) {
        onMain { $0.delegate?.audioDeactivated(audioSession) }
    }

    private func onMain(_ body: @escaping @MainActor (LiveCommunicationCallSystem) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                if let system { body(system) }
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let system = self.system { body(system) }
                }
            }
        }
    }
}
