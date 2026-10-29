import Foundation
import Observation

/// Typing dots and read receipts for one chat, with Tidex's timings.
///
/// While the person types, the server hears "typing" at most every 2.5 seconds, and
/// "stopped" after 4 seconds without a keystroke, on send, on an emptied field, or on
/// leaving. The partner's dots show while the server says they type. The server ends
/// that 4 seconds after their last heartbeat, such as when their app was killed. The
/// dots hide 2 seconds after typing ends, and right away when their message arrives.
@MainActor
@Observable
final class ThreadChatPresenceModel {
    private enum Timing {
        static let typingRefreshInterval: TimeInterval = 2.5
        static let typingIdleStop: Duration = .seconds(4)
        static let remoteStopGrace: Duration = .seconds(2)
        static let readDebounce: Duration = .milliseconds(200)
    }

    private(set) var partnerIsTyping = false
    private(set) var partnerLastReadMessageID: UUID?

    private let coupleID: UUID
    private let subject: ThreadChatSubject
    private let service: any ThreadChatServicing
    private let now: () -> Date

    private var typingWrite: Task<Void, Never>?
    private var didSendTypingStart = false
    private var lastTypingStartSentAt: Date?
    private var idleStopTask: Task<Void, Never>?
    private var lastRemoteTyping = false
    private var remoteTypingTask: Task<Void, Never>?
    private var lastMarkedMessageID: UUID?
    private var readTask: Task<Void, Never>?

    init(
        coupleID: UUID,
        subject: ThreadChatSubject,
        service: any ThreadChatServicing,
        now: @escaping () -> Date = Date.init
    ) {
        self.coupleID = coupleID
        self.subject = subject
        self.service = service
        self.now = now
    }

    // MARK: - Own typing

    func draftChanged(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Task { await stopTyping() }
            return
        }
        sendTypingStartIfNeeded()
        idleStopTask?.cancel()
        idleStopTask = Task { [weak self] in
            try? await Task.sleep(for: Timing.typingIdleStop)
            guard !Task.isCancelled else { return }
            await self?.stopTyping()
        }
    }

    /// Sends "stopped", but only after a "typing" went out.
    func stopTyping() async {
        idleStopTask?.cancel()
        idleStopTask = nil
        guard didSendTypingStart else { return }
        didSendTypingStart = false
        lastTypingStartSentAt = nil
        await enqueueTyping(false).value
    }

    private func sendTypingStartIfNeeded() {
        if let lastTypingStartSentAt, now().timeIntervalSince(lastTypingStartSentAt) < Timing.typingRefreshInterval {
            return
        }
        lastTypingStartSentAt = now()
        didSendTypingStart = true
        enqueueTyping(true)
    }

    @discardableResult
    private func enqueueTyping(_ isTyping: Bool) -> Task<Void, Never> {
        let previous = typingWrite
        let task = Task { [service, coupleID, subject] in
            await previous?.value
            await service.setTyping(coupleID: coupleID, subject: subject, isTyping: isTyping)
        }
        typingWrite = task
        return task
    }

    // MARK: - Partner

    /// Follows the partner's typing and read state until the calling task ends.
    func observe() async {
        for await presence in service.livePresence(coupleID: coupleID, subject: subject) {
            apply(presence)
        }
        remoteTypingTask?.cancel()
    }

    func apply(_ presence: ThreadChatPresence) {
        partnerLastReadMessageID = presence.partnerLastReadMessageID
        guard presence.partnerIsTyping != lastRemoteTyping else { return }
        lastRemoteTyping = presence.partnerIsTyping
        remoteTypingTask?.cancel()

        if presence.partnerIsTyping {
            partnerIsTyping = true
        } else if partnerIsTyping {
            remoteTypingTask = hideTyping(after: Timing.remoteStopGrace)
        }
    }

    /// The partner's message replaces their dots at once, with no grace. The server
    /// only reports changes, so if it still says they type after the grace, they are
    /// writing the next message and the dots come back.
    func partnerMessageArrived() {
        remoteTypingTask?.cancel()
        partnerIsTyping = false
        guard lastRemoteTyping else { return }
        remoteTypingTask = Task { [weak self] in
            try? await Task.sleep(for: Timing.remoteStopGrace)
            guard !Task.isCancelled, let self, lastRemoteTyping else { return }
            partnerIsTyping = true
        }
    }

    private func hideTyping(after delay: Duration) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.partnerIsTyping = false
        }
    }

    // MARK: - Read receipts

    /// Tells the server the person has seen the thread up to `messageID`, shortly after
    /// it shows, so a burst of messages sends one mark.
    func markRead(threadID: UUID, messageID: UUID) {
        guard messageID != lastMarkedMessageID else { return }
        readTask?.cancel()
        readTask = Task { [weak self, service] in
            try? await Task.sleep(for: Timing.readDebounce)
            guard !Task.isCancelled, let self else { return }
            lastMarkedMessageID = messageID
            await service.markThreadReadOnServer(threadID: threadID, messageID: messageID)
        }
    }
}
