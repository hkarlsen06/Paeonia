import Foundation
import Observation

@MainActor
@Observable
final class DailyQuestionChatViewModel {
    enum Notice: Equatable {
        case loadFailed
        case sendFailed
        case messageTooLong
        case unavailable
    }

    static let maximumMessageLength = 4_000

    let question: DailyChallengeQuestion
    private let service: any DailyQuestionChatServicing
    private let operationProvider: any SyncClientOperationProviding
    private var syncAfterLocalChange: (@MainActor () async -> Void)?
    private(set) var participants: DailyChallengeParticipants
    private(set) var messages: [DailyQuestionChatMessage] = []
    private(set) var threadID: UUID?
    private(set) var isLoading = false
    private(set) var notice: Notice?
    private var hasQueuedThreadCreation = false

    init(
        question: DailyChallengeQuestion,
        participants: DailyChallengeParticipants,
        service: (any DailyQuestionChatServicing)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        syncAfterLocalChange: (@MainActor () async -> Void)? = nil
    ) {
        self.question = question
        self.participants = participants
        self.service = service ?? DailyQuestionChatServiceFactory.makeDefault()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.syncAfterLocalChange = syncAfterLocalChange
    }

    var isChatAvailable: Bool {
        question.isChatAvailable && participants.currentUserID != nil
    }

    var hasSendingMessages: Bool {
        messages.contains(where: \.isSending)
    }

    func refreshParticipants(_ participants: DailyChallengeParticipants) {
        self.participants = participants
    }

    func load(surfacingFailure: Bool = true) async {
        guard let ownerUserID = participants.currentUserID else {
            notice = .unavailable
            return
        }
        guard question.isChatAvailable else {
            notice = .unavailable
            return
        }

        isLoading = messages.isEmpty
        defer { isLoading = false }

        let cachedSummaries = await service.cachedThreadSummaries(ownerUserID: ownerUserID)
        threadID = cachedSummaries.first(where: { $0.instanceID == question.id })?.threadID
        let cached = await service.cachedMessages(ownerUserID: ownerUserID, instanceID: question.id)
        let pending = await service.pendingMessages(ownerUserID: ownerUserID, instanceID: question.id)
        hasQueuedThreadCreation = await service.hasPendingThreadCreation(
            ownerUserID: ownerUserID,
            instanceID: question.id
        )
        messages = DailyQuestionChatMessage.visibleOrdered(remote: cached, optimistic: pending)
        if messages.contains(where: \.sendFailed) {
            notice = .sendFailed
        }

        do {
            let summaries = try await service.refreshThreadSummaries(ownerUserID: ownerUserID)
            threadID = summaries.first(where: { $0.instanceID == question.id })?.threadID ?? threadID
            if let threadID {
                let remote = try await service.refreshMessages(
                    ownerUserID: ownerUserID,
                    instanceID: question.id,
                    threadID: threadID
                )
                let stillPending = await service.pendingMessages(
                    ownerUserID: ownerUserID,
                    instanceID: question.id
                )
                messages = DailyQuestionChatMessage.visibleOrdered(remote: remote, optimistic: stillPending)
                hasQueuedThreadCreation = await service.hasPendingThreadCreation(
                    ownerUserID: ownerUserID,
                    instanceID: question.id
                )
            }
        } catch {
            if surfacingFailure, !isCancellation(error), messages.isEmpty {
                notice = .loadFailed
            }
        }
    }

    func send(_ text: String) async -> Bool {
        guard let ownerUserID = participants.currentUserID, question.isChatAvailable else {
            notice = .unavailable
            return false
        }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        guard body.count <= Self.maximumMessageLength else {
            notice = .messageTooLong
            return false
        }

        let createThread = threadID == nil && !hasQueuedThreadCreation
        do {
            let message = try await service.queueMessage(
                ownerUserID: ownerUserID,
                coupleID: question.coupleID,
                instanceID: question.id,
                threadID: threadID,
                body: body,
                createThread: createThread,
                operation: operationProvider.makeOperation()
            )
            if createThread { hasQueuedThreadCreation = true }
            messages = DailyQuestionChatMessage.visibleOrdered(remote: messages, optimistic: [message])
            syncInBackground()
            return true
        } catch {
            notice = .sendFailed
            return false
        }
    }

    func dismissNotice() {
        notice = nil
    }

    private func syncInBackground() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await syncAfterLocalChange?()
            await load(surfacingFailure: false)
        }
    }

    private nonisolated func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

extension DailyQuestionChatViewModel.Notice {
    var title: LocalizedStringResource {
        switch self {
        case .loadFailed: .dailyChatErrorLoadTitle
        case .sendFailed: .dailyChatErrorSendTitle
        case .messageTooLong: .dailyChatErrorTooLongTitle
        case .unavailable: .dailyChatErrorUnavailableTitle
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .loadFailed: .dailyChatErrorLoadMessage
        case .sendFailed: .dailyChatErrorSendMessage
        case .messageTooLong: .dailyChatErrorTooLongMessage
        case .unavailable: .dailyChatErrorUnavailableMessage
        }
    }
}
