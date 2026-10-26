import SwiftUI

/// What a memory's comments or a story's replies need to open as a chat: the couple, both
/// partners' names, the chat service, the sync that sends queued messages, and the report
/// flow. The Questions tab opens story chats with it too, and builds its question chats
/// from the daily view model. The tab view sets this once, so the Memories, Stories and
/// Questions screens need none of it passed down.
struct ThreadChatContext {
    var coupleID: UUID?
    var participants = DailyChallengeParticipants()
    var summaries: ThreadChatSummaries?
    var service: (any ThreadChatServicing)?
    var operationProvider: (any SyncClientOperationProviding)?
    var syncAfterLocalChange: (@MainActor () async -> Void)?
    var reporting = ChatReporting()

    /// Whether chats can open at all. Previews and a phone without a couple have none.
    var isAvailable: Bool {
        coupleID != nil && participants.currentUserID != nil
    }

    /// The chat view model for `subject`, read from this phone's copy so its first frame is complete.
    /// Nil without a couple.
    @MainActor
    func makeViewModel(subject: ThreadChatSubject, header: ThreadChatHeader) async -> ThreadChatViewModel? {
        guard let coupleID else { return nil }
        let viewModel = ThreadChatViewModel(
            subject: subject,
            coupleID: coupleID,
            header: header,
            participants: participants,
            service: service,
            operationProvider: operationProvider,
            syncAfterLocalChange: syncAfterLocalChange
        )
        await viewModel.prepare()
        return viewModel
    }
}

/// What reporting a chat message needs. The same pieces the Questions tab hands to its chat.
struct ChatReporting {
    var service: (any PrivacySafetyServicing)?
    var operationProvider: (any SyncClientOperationProviding)?
    var onReportedAndLeft: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var threadChatContext = ThreadChatContext()
}
