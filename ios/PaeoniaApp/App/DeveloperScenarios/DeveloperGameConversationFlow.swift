#if DEBUG
  import Foundation

  /// The production root, game, chat, cache and outbox with only the remote endpoint replaced.
  @MainActor
  struct DeveloperGameConversationFlow {
    let chat: ThreadChatService
    let sync: PaeoniaSyncService
    let games: GamesViewModel

    init(pending: any PendingSyncOperationPersisting) {
      let gateway = DeveloperGameConversationGateway()
      let cache = InMemoryThreadChatCache()
      chat = ThreadChatService(gateway: gateway, cache: cache, pendingOperationStore: pending)
      sync = PaeoniaSyncService(
        streams: [
          PendingSyncOperationDrainStream(handlers: [
            CreateChatThreadOperationHandler(gateway: gateway, cache: cache),
            SendChatMessageOperationHandler(gateway: gateway, cache: cache),
          ])
        ],
        stateStore: InMemorySyncStateRepository(),
        pendingOperationStore: pending,
        localPrivacyPurger: NoOpLocalPrivacyPurger()
      )
      games = GamesViewModel(dependencies: DeveloperGamesScenarioFactory.dependencies(for: .mindMeldOver))
    }
  }

  private actor DeveloperGameConversationGateway: ThreadChatGateway {
    private var summaries: [ThreadChatSummary] = []
    private var messages: [ThreadChatMessage] = []
    private let threadID = UUID()

    func loadThreadSummaries() -> [ThreadChatSummary] { summaries }

    func loadGameResult(coupleID _: UUID, source _: GameConversationSource) async throws -> GameConversationResult? {
      await MainActor.run {
        guard let game = DeveloperMindMeldScenarioFactory.state(for: .mindMeldOver)?.current else { return nil }
        return .mindMeld(
          RemoteMindMeldHistoryGame(
            id: game.id, gameNumber: game.gameNumber, state: game.state,
            endReason: game.endReason, endedByUserID: game.endedByUserID, createdAt: game.createdAt,
            endedAt: game.endedAt, meldNumber: game.meldNumber,
            rounds: game.rounds.compactMap { round in
              guard let mine = round.myWord, let theirs = round.partnerWord, let outcome = round.outcome else {
                return nil
              }
              return RemoteMindMeldHistoryRound(
                roundNumber: round.roundNumber, myWord: mine, partnerWord: theirs,
                outcome: outcome, countedByUserID: round.countedByUserID
              )
            }
          ))
      }
    }

    func loadMessages(threadID _: UUID, subjectID _: UUID, before _: ThreadChatMessageCursor?) -> ThreadChatMessagePage
    {
      ThreadChatMessagePage(messages: messages, hasMore: false)
    }

    func createThreadWithMessage(
      _ payload: CreateChatThreadPayload, mediaAssetIDs _: [UUID], operation: SyncClientOperation
    ) -> ThreadChatMessageResponse {
      record(body: payload.body, subject: payload.subject, coupleID: payload.coupleID, operation: operation)
    }

    func sendMessage(
      threadID _: UUID, body: String, mediaAssetIDs _: [UUID], replyTo _: ThreadChatItemID?,
      operation: SyncClientOperation
    ) throws -> ThreadChatMessageResponse {
      guard let summary = summaries.first else { throw ThreadChatServiceError.unavailable }
      return record(body: body, subject: summary.subject, coupleID: summary.coupleID, operation: operation)
    }

    private func record(body: String, subject: ThreadChatSubject, coupleID: UUID, operation: SyncClientOperation)
      -> ThreadChatMessageResponse
    {
      let message = ThreadChatMessage(
        id: UUID(), threadID: threadID, subjectID: subject.id, senderUserID: DeveloperScenarioFixture.currentUserID,
        body: body, createdAt: operation.localCreatedAt, clientOperationID: operation.id, isSending: false
      )
      messages.append(message)
      summaries = [
        ThreadChatSummary(
          threadID: threadID, coupleID: coupleID, subject: subject,
          createdAt: messages[0].createdAt, updatedAt: message.createdAt,
          lastMessageID: message.id, lastMessageAt: message.createdAt,
          lastMessageSenderUserID: message.senderUserID, lastMessageBody: body
        )
      ]
      return ThreadChatMessageResponse(threadID: threadID, messageID: message.id)
    }
  }
#endif
