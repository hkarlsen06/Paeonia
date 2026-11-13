import Foundation
import Observation

/// Whether the partner is in one chat, typing in it, and how far they have read.
nonisolated struct ThreadChatPresence: Equatable, Sendable {
    var partnerIsInChat = false
    var partnerIsTyping = false
    var partnerLastReadMessageID: UUID?

    static let none = ThreadChatPresence()
}

/// Typing dots, the open chat and read receipts for one chat, with Tidex's timings.
///
/// While the chat is on screen, the server hears "open" every 10 seconds and "closed"
/// when it leaves, so the partner's game can say they are in the chat. While the
/// person types, the server hears "typing" at most every 2.5 seconds, and "stopped"
/// after 4 seconds without a keystroke, on send, on an emptied field, or on leaving.
/// The partner's dots show while the server says they type. The server ends that
/// 4 seconds after their last heartbeat, such as when their app was killed. The dots
/// hide 2 seconds after typing ends, and right away when their message arrives.
@Observable
final class ThreadChatPresenceModel {
    private enum Timing {
        static let typingRefreshInterval: TimeInterval = 2.5
        static let typingIdleStop: Duration = .seconds(4)
        static let remoteStopGrace: Duration = .seconds(2)
        static let readDebounce: Duration = .milliseconds(200)
        /// The server ends an open chat 30 seconds after the last heartbeat.
        static let openHeartbeat: Duration = .seconds(10)
    }

    private(set) var partnerIsInChat = false
    private(set) var partnerIsTyping = false
    private(set) var partnerLastReadMessageID: UUID?

    private let coupleID: UUID
    private let subject: ThreadChatSubject
    private let service: any ThreadChatServicing
    private let now: () -> Date

    /// The last presence write, so typing and open writes reach the server in order.
    private var presenceWrite: Task<Void, Never>?
    private var isOnScreen = false
    private var openHeartbeat: Task<Void, Never>?
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

    // MARK: - Own presence

    /// The chat came on screen or left it, or the app moved to or from the front.
    func setOnScreen(_ onScreen: Bool) {
        guard onScreen != isOnScreen else { return }
        isOnScreen = onScreen
        openHeartbeat?.cancel()
        guard onScreen else {
            enqueueWrite { service, coupleID, subject in
                await service.setChatOpen(coupleID: coupleID, subject: subject, isOpen: false)
            }
            return
        }
        openHeartbeat = Task { [weak self] in
            while !Task.isCancelled {
                guard let write = self?.enqueueWrite({ service, coupleID, subject in
                    await service.setChatOpen(coupleID: coupleID, subject: subject, isOpen: true)
                }) else { return }
                // A slow server gets one heartbeat at a time, so none queue up behind the close.
                await write.value
                try? await Task.sleep(for: Timing.openHeartbeat)
            }
        }
    }

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
        await enqueueWrite { service, coupleID, subject in
            await service.setTyping(coupleID: coupleID, subject: subject, isTyping: false)
        }.value
    }

    private func sendTypingStartIfNeeded() {
        if let lastTypingStartSentAt, now().timeIntervalSince(lastTypingStartSentAt) < Timing.typingRefreshInterval {
            return
        }
        lastTypingStartSentAt = now()
        didSendTypingStart = true
        enqueueWrite { service, coupleID, subject in
            await service.setTyping(coupleID: coupleID, subject: subject, isTyping: true)
        }
    }

    @discardableResult
    private func enqueueWrite(
        _ write: @escaping (any ThreadChatServicing, UUID, ThreadChatSubject) async -> Void
    ) -> Task<Void, Never> {
        let previous = presenceWrite
        let task = Task { [service, coupleID, subject] in
            await previous?.value
            await write(service, coupleID, subject)
        }
        presenceWrite = task
        return task
    }

    // MARK: - Partner

    /// Follows the partner's typing and read state until the calling task ends.
    func observe() async {
        for await presence in service.livePresence(coupleID: coupleID, subject: subject) {
            apply(presence)
        }
        remoteTypingTask?.cancel()
        partnerIsInChat = false
    }

    func apply(_ presence: ThreadChatPresence) {
        partnerIsInChat = presence.partnerIsInChat
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
