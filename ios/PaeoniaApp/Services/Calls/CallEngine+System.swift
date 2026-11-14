import AVFoundation
import Foundation
@preconcurrency import LiveCommunicationKit

/// The system call UI's actions and audio. Every action ends in `fulfill` or `fail`, or the
/// system call UI gets stuck.
extension CallEngine {
    func handle(_ action: ConversationAction) {
        switch action {
        case let action as StartConversationAction:
            handleStart(action)
        case let action as JoinConversationAction:
            handleJoin(action)
        case let action as EndConversationAction:
            handleEnd(action)
        case let action as MuteConversationAction:
            handleMute(action)
        default:
            // Paeonia calls cannot pause, merge, play tones or translate.
            action.fail()
        }
    }

    func handleTimeout(_ action: ConversationAction) {
        guard let run, action.conversationUUID == run.conversationID,
              action is StartConversationAction || action is JoinConversationAction
        else {
            return
        }
        send(.failed(.other), to: run)
    }

    /// The system activated the call's audio. WebRTC's audio starts only now.
    func audioActivated(_ audioSession: AVAudioSession) {
        CallAudio.didActivate(audioSession)
        if let run, !run.isFinished {
            send(.audioActivated, to: run)
        }
        refreshAudioRoute()
    }

    func audioDeactivated(_ audioSession: AVAudioSession) {
        CallAudio.didDeactivate(audioSession)
    }

    /// The system dropped every call, such as after its call service restarted.
    func systemReset() {
        if let run, !run.isFinished {
            run.isEndingFromSystem = true
            send(.failed(.other), to: run)
        }
    }

    private func handleEnd(_ action: EndConversationAction) {
        if let run, run.conversationID == action.conversationUUID, !run.isFinished {
            run.isEndingFromSystem = true
            send(.hangUp, to: run)
        }
        action.fulfill(dateEnded: .now)
    }

    private func handleMute(_ action: MuteConversationAction) {
        if let run, run.conversationID == action.conversationUUID {
            applyMute(action.isMuted, in: run)
        }
        action.fulfill()
    }
}

/// What the system call UI shows about the call.
extension CallEngine {
    func conversation(of run: CallRun) -> Conversation? {
        manager.conversations.first { $0.uuid == run.conversationID }
    }

    func reportProgress(of run: CallRun, from previous: CallPhase) {
        guard run.machine.direction == .outgoing, let conversation = conversation(of: run) else { return }
        switch (previous, run.machine.phase) {
        case (.ringing, .connecting):
            manager.reportConversationEvent(.conversationStartedConnecting(.now), for: conversation)
        case (.connecting, .active):
            manager.reportConversationEvent(.conversationConnected(.now), for: conversation)
        default:
            break
        }
    }

    /// Says whether the call shows video, and never allows pausing or merging.
    func reportCapabilities(of run: CallRun) {
        guard let conversation = conversation(of: run), let session = center?.session else { return }
        let hasVideo = session.isCameraOn || session.isPartnerCameraOn
        let update = Conversation.Update(capabilities: hasVideo ? [.video] : [])
        manager.reportConversationEvent(.conversationUpdated(update), for: conversation)
    }

    static func systemReason(_ reason: CallEndReason) -> Conversation.EndedReason {
        switch reason {
        case .hungUp:
            .remoteEnded
        case .noAnswer, .missed:
            .unanswered
        case .answeredElsewhere:
            .joinedElsewhere
        case .busy, .failed:
            .failed
        }
    }
}

/// Receives LiveCommunicationKit's callbacks, which may arrive on any thread, and hands each to
/// the engine on the main thread in the order they came.
nonisolated final class CallConversationDelegate: ConversationManagerDelegate, @unchecked Sendable {
    /// Set once at launch. Read on the main thread only.
    nonisolated(unsafe) weak var engine: CallEngine?

    func conversationManager(_ manager: ConversationManager, conversationChanged conversation: Conversation) {}

    func conversationManagerDidBegin(_ manager: ConversationManager) {}

    func conversationManagerDidReset(_ manager: ConversationManager) {
        onMain { $0.systemReset() }
    }

    func conversationManager(_ manager: ConversationManager, perform action: ConversationAction) {
        nonisolated(unsafe) let action = action
        onMain { $0.handle(action) }
    }

    func conversationManager(_ manager: ConversationManager, timedOutPerforming action: ConversationAction) {
        nonisolated(unsafe) let action = action
        onMain { $0.handleTimeout(action) }
    }

    func conversationManager(_ manager: ConversationManager, didActivate audioSession: AVAudioSession) {
        onMain { $0.audioActivated(audioSession) }
    }

    func conversationManager(_ manager: ConversationManager, didDeactivate audioSession: AVAudioSession) {
        onMain { $0.audioDeactivated(audioSession) }
    }

    private func onMain(_ body: @escaping @MainActor (CallEngine) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                if let engine { body(engine) }
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let engine = self.engine { body(engine) }
                }
            }
        }
    }
}
