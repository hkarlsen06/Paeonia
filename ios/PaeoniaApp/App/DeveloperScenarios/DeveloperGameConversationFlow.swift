#if DEBUG
  import Foundation

  /// The production root, game, chat, cache and outbox with only the remote endpoint replaced.
  @MainActor
  struct DeveloperGameConversationFlow {
    let chat: ThreadChatService
    let sync: PaeoniaSyncService
    let games: GamesViewModel
    private let gateway: DeveloperGameConversationGateway

    /// `games` is the game scenario whose state the Games tab shows.
    init(
      pending: any PendingSyncOperationPersisting, games scenario: DeveloperScenario = .mindMeldWrite,
      result: GameConversationResult? = nil
    ) {
      let gateway = DeveloperGameConversationGateway(
        result: result ?? Self.historicalResult(), presence: DeveloperChatPresenceFeed())
      self.gateway = gateway
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
      games = GamesViewModel(dependencies: DeveloperGamesScenarioFactory.dependencies(for: scenario))
    }

    func receivePartnerMessage() async {
      await gateway.receivePartnerMessage()
      _ = try? await chat.refreshThreadSummaries(
        ownerUserID: DeveloperScenarioFixture.currentUserID)
      try? await chat.refreshGameTimeline(
        ownerUserID: DeveloperScenarioFixture.currentUserID,
        subject: GameChatSubject(coupleID: DeveloperScenarioFixture.coupleID, kind: .mindMeld))
      LocalStoreChanges.post(.threadChat, ownerUserID: DeveloperScenarioFixture.currentUserID)
    }

    /// Plays the partner opening the Mind Meld chat, typing, then leaving, a few seconds apart.
    func playPartnerInChat() async {
      let steps: [ThreadChatPresence] = [
        .init(partnerIsInChat: true), .init(partnerIsInChat: true, partnerIsTyping: true),
        .init(partnerIsInChat: true), .none,
      ]
      for step in steps {
        gateway.presence.send(step)
        try? await Task.sleep(for: .seconds(4))
      }
    }

    private static func historicalResult() -> GameConversationResult? {
      guard let game = DeveloperMindMeldScenarioFactory.state(for: .mindMeldOver)?.current,
        case .mindMeld(let history)? = game.conversationResult,
        let historicalID = UUID(uuidString: "a9000000-0000-4000-8000-000000000001")
      else { return nil }
      return .mindMeld(
        RemoteMindMeldHistoryGame(
          id: historicalID,
          gameNumber: max(1, history.gameNumber - 1), state: history.state,
          endReason: history.endReason,
          endedByUserID: history.endedByUserID, createdAt: history.createdAt,
          endedAt: history.endedAt, meldNumber: history.meldNumber, rounds: history.rounds))
    }
  }

  /// The partner's presence in the local flow's chats, sent by the debug controls.
  @MainActor
  final class DeveloperChatPresenceFeed {
    private var continuations: [UUID: AsyncStream<ThreadChatPresence>.Continuation] = [:]
    private var latest = ThreadChatPresence.none

    func send(_ presence: ThreadChatPresence) {
      latest = presence
      for continuation in continuations.values { continuation.yield(presence) }
    }

    nonisolated func stream() -> AsyncStream<ThreadChatPresence> {
      AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        let id = UUID()
        Task { @MainActor in
          continuations[id] = continuation
          continuation.yield(latest)
        }
        continuation.onTermination = { _ in Task { @MainActor in self.continuations[id] = nil } }
      }
    }
  }

  private actor DeveloperGameConversationGateway: ThreadChatGateway {
    nonisolated let presence: DeveloperChatPresenceFeed
    private var summaries: [ThreadChatSummary] = []
    private var messages: [ThreadChatMessage] = []
    /// One thread per chat, such as the Mind Meld chat and the couple chat.
    private var threadIDs: [ThreadChatSubject: UUID] = [:]
    private let result: GameConversationResult?

    init(result: GameConversationResult?, presence: DeveloperChatPresenceFeed) {
      self.result = result
      self.presence = presence
    }

    nonisolated func livePresence(coupleID _: UUID, subject _: ThreadChatSubject) -> AsyncStream<ThreadChatPresence> {
      presence.stream()
    }

    func loadThreadSummaries() -> [ThreadChatSummary] { summaries }

    func receivePartnerMessage() {
      _ = record(
        body: "Your move!",
        subject: .game(
          GameChatSubject(coupleID: DeveloperScenarioFixture.coupleID, kind: .mindMeld)),
        coupleID: DeveloperScenarioFixture.coupleID, replyTo: nil,
        operation: SyncClientOperation(clientID: UUID(), clientSequence: 1, localCreatedAt: .now),
        senderUserID: DeveloperScenarioFixture.partnerUserID)
    }

    func loadGameResult(coupleID _: UUID, source: GameConversationSource) -> GameConversationResult?
    {
      guard reference?.source == source else { return nil }
      return result
    }

    private var reference: GameChatResultReference? {
      guard case .mindMeld(let game)? = result else { return nil }
      return GameChatResultReference(
        source: .mindMeld(game.id), finishedAt: result?.date ?? game.createdAt,
        key: game.id.uuidString.lowercased())
    }

    func loadGameTimeline(subject: GameChatSubject, before _: GameChatTimelineCursor?)
      -> GameChatTimeline
    {
      GameChatTimeline(
        threadID: summaries.first { $0.subject == .game(subject) }?.threadID,
        messages: messages.filter { $0.subjectID == subject.id },
        results: reference.flatMap { $0.source.kind == subject.kind ? [$0] : nil } ?? [], hasMore: false)
    }

    func loadMessages(threadID: UUID, subjectID _: UUID, before _: ThreadChatMessageCursor?)
      -> ThreadChatMessagePage
    {
      ThreadChatMessagePage(messages: messages.filter { $0.threadID == threadID }, hasMore: false)
    }

    func createThreadWithMessage(
      _ payload: CreateChatThreadPayload, mediaAssetIDs _: [UUID], operation: SyncClientOperation
    ) -> ThreadChatMessageResponse {
      record(
        body: payload.body, subject: payload.subject, coupleID: payload.coupleID,
        replyTo: payload.replyToGameResultSource.map(ThreadChatItemID.gameResult),
        operation: operation)
    }

    func sendMessage(
      threadID: UUID, body: String, mediaAssetIDs _: [UUID], replyTo: ThreadChatItemID?,
      operation: SyncClientOperation
    ) throws -> ThreadChatMessageResponse {
      guard let summary = summaries.first(where: { $0.threadID == threadID }) else {
        throw ThreadChatServiceError.unavailable
      }
      return record(
        body: body, subject: summary.subject, coupleID: summary.coupleID,
        replyTo: replyTo, operation: operation)
    }

    private func record(
      body: String, subject: ThreadChatSubject, coupleID: UUID,
      replyTo: ThreadChatItemID?, operation: SyncClientOperation,
      senderUserID: UUID = DeveloperScenarioFixture.currentUserID
    )
      -> ThreadChatMessageResponse
    {
      let threadID = threadIDs[subject] ?? UUID()
      threadIDs[subject] = threadID
      let message = ThreadChatMessage(
        id: UUID(), threadID: threadID, subjectID: subject.id, senderUserID: senderUserID,
        body: body, createdAt: operation.localCreatedAt, clientOperationID: operation.id,
        delivery: .sent, replyTo: replyTo
      )
      messages.append(message)
      let firstInThread = messages.first { $0.threadID == threadID } ?? message
      summaries.removeAll { $0.subject == subject }
      summaries.append(
        ThreadChatSummary(
          threadID: threadID, coupleID: coupleID, subject: subject,
          createdAt: firstInThread.createdAt, updatedAt: message.createdAt,
          lastMessageID: message.id, lastMessageAt: message.createdAt,
          lastMessageSenderUserID: message.senderUserID, lastMessageBody: body
        ))
      return ThreadChatMessageResponse(threadID: threadID, messageID: message.id)
    }
  }

  /// Local flows that open straight into a game, to see its chat panel over it.
  nonisolated extension DeveloperScenario {
    static let localFlowGameChatDrawing = DeveloperScenario(
      "local-flow-game-chat-drawing", "Local flow · chat over Draw & Guess",
      "Open the chat while Robin draws. The drawing stays in view above it", .localFlows
    ) { _ in
      DeveloperLocalFlowHost(
        seed: .paired, gameConversation: .drawWatchingLive, launchLink: "paeonia://games/draw-and-guess")
    }

    static let localFlowGameChatBoard = DeveloperScenario(
      "local-flow-game-chat-board", "Local flow · chat over Four in a Row",
      "Open the chat on Robin's turn. The board stays in view above it", .localFlows
    ) { _ in
      DeveloperLocalFlowHost(
        seed: .paired, gameConversation: .connectFourPartnerTurn, launchLink: "paeonia://games/connect-four")
    }
  }
#endif
