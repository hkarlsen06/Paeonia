#if DEBUG
  import Foundation
  import StoreKit

  enum DeveloperScenarioFixture {
    nonisolated static let currentUserID =
      UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    nonisolated static let partnerUserID =
      UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()
    nonisolated static let coupleID =
      UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()
    nonisolated static let now = Date(timeIntervalSince1970: 1_784_203_200)

    static var completeSession: AuthSession {
      AuthSession(
        id: currentUserID.uuidString,
        provider: .development,
        displayName: "Alex",
        timeZoneID: "Europe/Oslo",
        profilePhotoAssetID: nil,
        profileStatus: .complete
      )
    }

    static func memoryRecords() -> [MemoryRecord] {
      [
        memoryRecord(
          id: "aaaaaaa1-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          title: "Our first weekend away",
          date: "2026-07-12",
          ownNote: "The rainy walk ended up being my favourite part.",
          partnerNote: "And the tiny café with the blue door."
        ),
        memoryRecord(
          id: "aaaaaaa2-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          title: "Late-night pancakes",
          date: "2026-06-28",
          ownNote: "We used far too much cinnamon.",
          partnerNote: nil
        ),
        memoryRecord(
          id: "aaaaaaa3-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          title: "The concert",
          date: "2026-05-17",
          ownNote: nil,
          partnerNote: "I still hear that last song when I see this."
        ),
      ]
    }

    private static func memoryRecord(
      id: String,
      title: String,
      date: String,
      ownNote: String?,
      partnerNote: String?
    ) -> MemoryRecord {
      let memoryID = UUID(uuidString: id) ?? UUID()
      let timestamp = now.addingTimeInterval(-Double(memoryRecordsOffset(for: date)))
      return MemoryRecord(
        snapshot: MemorySnapshot(
          ownerUserID: currentUserID,
          memoryID: memoryID,
          coupleID: coupleID,
          title: title,
          memoryDate: date,
          createdByUserID: currentUserID,
          lastEditedByUserID: currentUserID,
          revision: 1,
          moderationStatus: .visible,
          deletedAt: nil,
          createdAt: timestamp,
          updatedAt: timestamp,
          syncUpdatedAt: timestamp,
          ownNote: note(body: ownNote, userID: currentUserID, at: timestamp),
          partnerNote: note(body: partnerNote, userID: partnerUserID, at: timestamp),
          visibleMemoryMediaIDs: [],
          visibleMediaAssetIDs: [],
          media: [],
          threadID: nil
        )
      )
    }

    private static func note(body: String?, userID: UUID, at date: Date) -> MemoryNoteSnapshot? {
      guard let body else { return nil }
      return MemoryNoteSnapshot(
        noteID: UUID(),
        userID: userID,
        body: body,
        revision: 1,
        updatedAt: date,
        deletedAt: nil,
        moderationStatus: .visible
      )
    }

    private static func memoryRecordsOffset(for date: String) -> Int {
      switch date {
      case "2026-07-12": 86_400 * 4
      case "2026-06-28": 86_400 * 18
      default: 86_400 * 60
      }
    }
  }

  nonisolated enum DeveloperScenarioDailyFixture {
    nonisolated static let coupleDayID =
      UUID(uuidString: "77777777-7777-7777-7777-777777777777") ?? UUID()
    nonisolated static let questionID =
      UUID(uuidString: "88888888-8888-8888-8888-888888888888") ?? UUID()
  }

  actor DeveloperScenarioOfflineDailyOperationStore: PendingSyncOperationPersisting {
    private let storage = InMemoryPendingSyncOperationRepository()
    private var didSeed = false

    private func seedIfNeeded() async throws {
      guard !didSeed else { return }
      didSeed = true
      let payload = DailySubmitAnswerOperationPayload(
        instanceID: DeveloperScenarioDailyFixture.questionID,
        answerID: UUID(),
        content: .text("Saved here. Waiting for a connection.")
      )
      try await storage.enqueue(
        PendingSyncOperationRequest(
          ownerUserID: DeveloperScenarioFixture.currentUserID,
          operation: SyncClientOperation(
            clientID: UUID(),
            clientSequence: 1,
            localCreatedAt: DeveloperScenarioFixture.now
          ),
          operationKind: .submitDailyAnswer,
          idempotencyScope: "developer-offline-answer",
          requestData: try JSONEncoder().encode(payload)
        )
      )
    }

    func enqueue(_ request: PendingSyncOperationRequest) async throws {
      try await seedIfNeeded()
      try await storage.enqueue(request)
    }
    func readyOperations(ownerUserID: UUID, limit: Int, now: Date) async throws
      -> [PendingSyncOperationSnapshot]
    {
      try await seedIfNeeded()
      return try await storage.readyOperations(ownerUserID: ownerUserID, limit: limit, now: now)
    }
    func nextPendingOperationDate(ownerUserID: UUID, now: Date) async throws -> Date? {
      try await seedIfNeeded()
      return try await storage.nextPendingOperationDate(ownerUserID: ownerUserID, now: now)
    }
    func inFlightOperations(ownerUserID: UUID, kind: SyncPendingOperationKind) async throws
      -> [PendingSyncOperationSnapshot]
    {
      try await seedIfNeeded()
      return try await storage.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
    }
    func markSending(clientOperationID: UUID, at date: Date) async throws {
      try await seedIfNeeded()
      try await storage.markSending(clientOperationID: clientOperationID, at: date)
    }
    func markSucceeded(clientOperationID: UUID, at date: Date) async throws {
      try await seedIfNeeded()
      try await storage.markSucceeded(clientOperationID: clientOperationID, at: date)
    }
    func markRetryableFailure(
      clientOperationID: UUID, errorDescription: String, nextRetryAt: Date?, at date: Date
    ) async throws {
      try await seedIfNeeded()
      try await storage.markRetryableFailure(
        clientOperationID: clientOperationID, errorDescription: errorDescription,
        nextRetryAt: nextRetryAt, at: date)
    }
    func markTerminalFailure(clientOperationID: UUID, errorDescription: String, at date: Date)
      async throws
    {
      try await seedIfNeeded()
      try await storage.markTerminalFailure(
        clientOperationID: clientOperationID, errorDescription: errorDescription, at: date)
    }
    func deleteCompleted(ownerUserID: UUID) async throws {
      try await seedIfNeeded()
      try await storage.deleteCompleted(ownerUserID: ownerUserID)
    }
    func resetInFlight(ownerUserID: UUID) async throws {
      try await seedIfNeeded()
      try await storage.resetInFlight(ownerUserID: ownerUserID)
    }
  }

  @MainActor
  final class DeveloperScenarioOperationProvider:
    SyncClientOperationProviding,
    PairingClientOperationProviding
  {
    private let clientID = UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID()
    private var sequence: Int64 = 0

    func makeOperation() -> SyncClientOperation {
      sequence += 1
      return SyncClientOperation(
        clientID: clientID,
        clientSequence: sequence,
        localCreatedAt: DeveloperScenarioFixture.now
      )
    }
  }

  @MainActor
  final class DeveloperScenarioInviteStore: PairingInviteStoring {
    private var invite: PairingInvite?

    init(invite: PairingInvite? = nil) {
      self.invite = invite
    }

    func loadInvite(for _: String) -> PairingInvite? { invite }
    func saveInvite(_ invite: PairingInvite, for _: String) { self.invite = invite }
    func clearInvite(for _: String) { invite = nil }
  }

  actor DeveloperScenarioPairingService: PairingServicing {
    enum Mode: Equatable { case ready, expired, failing }
    private let mode: Mode

    init(mode: Mode) { self.mode = mode }

    func createInvite(operation _: PairingClientOperation, expiresAt: Date) async throws
      -> PairingInvite
    {
      guard mode != .failing else { throw PairingInviteCreationError.inviteCodeCollision }
      guard let joinURL = URL(string: "https://paeonia.no/join/LOVE26") else {
        throw URLError(.badURL)
      }
      return PairingInvite(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID(),
        code: "LOVE26",
        joinURL: joinURL,
        expiresAt: expiresAt
      )
    }

    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
      PairingInviteValidation(
        inviteID: invite.id,
        status: mode == .expired ? .expired : .pending,
        expiresAt: invite.expiresAt
      )
    }

    func previewInvite(codeInput _: String) async throws -> PairingInvitePreview? {
      guard mode != .failing else { throw URLError(.notConnectedToInternet) }
      guard mode != .expired else { return nil }
      return PairingInvitePreview(
        inviteID: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID(),
        inviterUserID: DeveloperScenarioFixture.partnerUserID,
        inviterDisplayName: "Robin",
        expiresAt: DeveloperScenarioFixture.now.addingTimeInterval(86_400),
        hasSafetyWarning: false
      )
    }
    func rotateInvite(
      currentInvite _: PairingInvite, operation: PairingClientOperation, expiresAt: Date
    ) async throws -> PairingInvite {
      try await createInvite(operation: operation, expiresAt: expiresAt)
    }
    func acceptInvite(
      codeInput _: String, operation _: PairingClientOperation, startedOn _: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
      PairingAcceptedRelationship(coupleID: DeveloperScenarioFixture.coupleID)
    }
    func revokeInvite(id _: UUID) async throws -> Bool { true }
    func leaveRelationship(operation _: PairingClientOperation) async throws -> Bool { true }
  }

  actor DeveloperScenarioMemoryDataService: MemoryDataServicing {
    private let repository: InMemoryMemoryRecordRepository
    private let service: MemoryDataService
    private let records: [MemoryRecord]
    private var didSeed = false

    init(records: [MemoryRecord]) {
      let repository = InMemoryMemoryRecordRepository()
      self.repository = repository
      self.records = records
      service = MemoryDataService(
        memoryStore: repository,
        pendingOperationStore: InMemoryPendingSyncOperationRepository()
      )
    }

    private func seedIfNeeded() async throws {
      guard !didSeed else { return }
      didSeed = true
      for record in records { try await repository.saveLocal(record) }
    }

    func loadCachedMemories(ownerUserID: UUID, includeHidden: Bool) async throws -> [MemoryRecord] {
      try await seedIfNeeded()
      return try await service.loadCachedMemories(
        ownerUserID: ownerUserID, includeHidden: includeHidden)
    }
    func loadCachedMemory(ownerUserID: UUID, memoryID: UUID) async throws -> MemoryRecord? {
      try await seedIfNeeded()
      return try await service.loadCachedMemory(ownerUserID: ownerUserID, memoryID: memoryID)
    }
    func createMemory(
      ownerUserID: UUID, coupleID: UUID, memoryID: UUID, title: String, memoryDate: String,
      noteBody: String?, optimisticMedia: [MemoryMediaSnapshot], operation: SyncClientOperation
    ) async throws -> MemoryRecord {
      try await service.createMemory(
        ownerUserID: ownerUserID, coupleID: coupleID, memoryID: memoryID, title: title,
        memoryDate: memoryDate, noteBody: noteBody, optimisticMedia: optimisticMedia,
        operation: operation)
    }
    func updateMemory(
      ownerUserID: UUID, memoryID: UUID, expectedRevision: Int, title: String, memoryDate: String,
      operation: SyncClientOperation
    ) async throws -> MemoryRecord {
      try await service.updateMemory(
        ownerUserID: ownerUserID, memoryID: memoryID, expectedRevision: expectedRevision,
        title: title, memoryDate: memoryDate, operation: operation)
    }
    func hideMemory(
      ownerUserID: UUID, memoryID: UUID, expectedRevision: Int, operation: SyncClientOperation
    ) async throws -> MemoryRecord {
      try await service.hideMemory(
        ownerUserID: ownerUserID, memoryID: memoryID, expectedRevision: expectedRevision,
        operation: operation)
    }
    func upsertMemoryNote(
      ownerUserID: UUID, memoryID: UUID, expectedRevision: Int?, body: String,
      operation: SyncClientOperation
    ) async throws -> MemoryRecord {
      try await service.upsertMemoryNote(
        ownerUserID: ownerUserID, memoryID: memoryID, expectedRevision: expectedRevision,
        body: body, operation: operation)
    }
    func attachMemoryMedia(
      ownerUserID: UUID, memoryID: UUID, optimisticMedia: [MemoryMediaSnapshot],
      operation: SyncClientOperation
    ) async throws -> MemoryRecord {
      try await service.attachMemoryMedia(
        ownerUserID: ownerUserID, memoryID: memoryID, optimisticMedia: optimisticMedia,
        operation: operation)
    }
    func removeMemoryMedia(
      ownerUserID: UUID, memoryID: UUID, memoryMediaID: UUID, operation: SyncClientOperation
    ) async throws -> MemoryRecord {
      try await service.removeMemoryMedia(
        ownerUserID: ownerUserID, memoryID: memoryID, memoryMediaID: memoryMediaID,
        operation: operation)
    }
    func createMemoryThreadMessage(
      ownerUserID: UUID, memoryID: UUID, body: String, mediaAssetIDs: [UUID],
      operation: SyncClientOperation
    ) async throws {
      try await service.createMemoryThreadMessage(
        ownerUserID: ownerUserID, memoryID: memoryID, body: body, mediaAssetIDs: mediaAssetIDs,
        operation: operation)
    }
  }

  struct DeveloperScenarioPushAuthorization: PushAuthorizationProviding {
    let denied: Bool
    func requestAuthorizationIfNeeded() async -> Bool { true }
    func isDenied() async -> Bool { denied }
  }

  @MainActor
  final class DeveloperScenarioStoreKitService: PaeoniaStoreKitServicing {
    private let blocksProductLoad: Bool
    var products: [Product] = []
    var restoredStreakCount: Int?

    init(blocksProductLoad: Bool = false) {
      self.blocksProductLoad = blocksProductLoad
    }

    func configure(userID _: String) {}
    func loadProducts() async throws {
      if blocksProductLoad {
        try await Task.sleep(for: .seconds(3_600))
      }
    }
    func eligibleFreeTrial(for _: PaeoniaSubscriptionProductID) async -> PaeoniaFreeTrial? { nil }
    func product(for _: PaeoniaSubscriptionProductID) -> Product? { nil }
    func product(for _: PaeoniaConsumableProductID) -> Product? { nil }
    func purchase(_: Product) async throws -> Bool { false }
    func restorePurchases() async throws -> Bool { false }
    func redeemStreakRestore() async throws -> Int? { restoredStreakCount }
    func recoverPendingStreakRestores() async -> Int? { restoredStreakCount }
  }
#endif
