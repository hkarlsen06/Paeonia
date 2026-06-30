import Foundation
import Testing
@testable import PaeoniaApp

// MARK: - Fixtures

private func fixedUUID(_ string: String) -> UUID {
    UUID(uuidString: string) ?? UUID()
}

private enum CacheTestIDs {
    static let ownerUserID = fixedUUID("aaaa0000-0000-0000-0000-000000000000")
    static let otherUserID = fixedUUID("bbbb0000-0000-0000-0000-000000000000")
    static let coupleID = fixedUUID("cccc0000-0000-0000-0000-000000000000")
    static let coupleDay = fixedUUID("dddd0000-0000-0000-0000-000000000000")
    static let startsAt = Date(timeIntervalSince1970: 1_782_432_000)
    static let endsAt = Date(timeIntervalSince1970: 1_782_518_400)
    static let generatedAt = Date(timeIntervalSince1970: 1_782_450_000)
    static let answerDate = Date(timeIntervalSince1970: 1_782_455_000)
}

/// Builds a minimal `DailyChallengeRemoteSnapshotRow` with one question and one
/// answer for use across multiple cache tests.
private func sampleSnapshotRow(
    ownerUserID: UUID = CacheTestIDs.ownerUserID
) -> DailyChallengeRemoteSnapshotRow {
    let questionRow = DailyQuestionRow(
        coupleDayID: CacheTestIDs.coupleDay,
        coupleID: CacheTestIDs.coupleID,
        localDate: "2026-06-27",
        effectiveLocalDate: nil,
        startsAt: CacheTestIDs.startsAt,
        endsAt: CacheTestIDs.endsAt,
        instanceID: fixedUUID("eeee0000-0000-0000-0000-000000000000"),
        seededForUserID: ownerUserID,
        slotNumber: 1,
        instanceStatus: "active",
        questionID: fixedUUID("ffff0000-0000-0000-0000-000000000000"),
        questionVersionID: fixedUUID("1111aaaa-0000-0000-0000-000000000000"),
        questionKey: "small_moment_today",
        promptEN: "What small moment made you think of us today?",
        shortPromptEN: "A small moment today",
        promptNB: "Hvilket lite øyeblikk fikk deg til å tenke på oss i dag?",
        shortPromptNB: "Et lite øyeblikk",
        answerKinds: [.text],
        ownAnswerID: nil,
        ownAnsweredAt: nil,
        partnerAnswerID: nil,
        partnerAnsweredAt: nil,
        canViewPartnerAnswer: false,
        isCurrentDay: true
    )

    let streakRow = CoupleStreakRow(
        currentCount: 7,
        longestCount: 12,
        lastQualifiedDate: "2026-06-26",
        restoreAvailable: false,
        restorableCount: 0,
        restoreDeadline: nil
    )

    return DailyChallengeRemoteSnapshotRow(
        questions: [questionRow],
        answerDetails: [],
        streak: streakRow,
        generatedAt: CacheTestIDs.generatedAt
    )
}

// MARK: - In-memory stand-in used in view-model tests

/// A thread-safe in-memory cache implementation for view-model seed tests.
/// Using `@unchecked Sendable` mirrors the pattern in `FileDailyAnswerMediaDraftStore`.
final class InMemoryDailyChallengeSnapshotCache: DailyChallengeSnapshotCaching, @unchecked Sendable {
    private var storage: [UUID: DailyChallengeRemoteSnapshotRow] = [:]
    private(set) var saveCount = 0
    private(set) var loadCount = 0
    private(set) var clearCount = 0

    func load(ownerUserID: UUID) -> DailyChallengeRemoteSnapshotRow? {
        loadCount += 1
        return storage[ownerUserID]
    }

    func save(_ row: DailyChallengeRemoteSnapshotRow, ownerUserID: UUID) {
        saveCount += 1
        storage[ownerUserID] = row
    }

    func clearAll() {
        clearCount += 1
        storage.removeAll()
    }
}

// MARK: - File cache tests

struct DailyChallengeSnapshotCacheTests {

    // MARK: Round-trip

    @Test func saveAndLoadReturnsEqualRowForSameOwner() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileDailyChallengeSnapshotCache(directoryURL: dir)
        let row = sampleSnapshotRow()

        cache.save(row, ownerUserID: CacheTestIDs.ownerUserID)
        let loaded = try #require(cache.load(ownerUserID: CacheTestIDs.ownerUserID))

        // Top-level fields
        #expect(loaded.generatedAt == row.generatedAt)
        #expect(loaded.questions.count == row.questions.count)
        #expect(loaded.streak?.currentCount == row.streak?.currentCount)
        #expect(loaded.streak?.longestCount == row.streak?.longestCount)
        #expect(loaded.streak?.lastQualifiedDate == row.streak?.lastQualifiedDate)

        // Question fields that must survive the round-trip
        let q = try #require(loaded.questions.first)
        #expect(q.instanceID == row.questions[0].instanceID)
        #expect(q.promptEN == row.questions[0].promptEN)
        #expect(q.answerKinds == row.questions[0].answerKinds)
        #expect(q.startsAt == row.questions[0].startsAt)
        #expect(q.isCurrentDay == row.questions[0].isCurrentDay)
    }

    @Test func loadForDifferentOwnerReturnsNil() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileDailyChallengeSnapshotCache(directoryURL: dir)
        let row = sampleSnapshotRow(ownerUserID: CacheTestIDs.ownerUserID)

        cache.save(row, ownerUserID: CacheTestIDs.ownerUserID)

        // A different user must never see another user's cached relationship content.
        let loaded = cache.load(ownerUserID: CacheTestIDs.otherUserID)
        #expect(loaded == nil)
    }

    // MARK: clearAll

    @Test func clearAllRemovesCachedContent() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileDailyChallengeSnapshotCache(directoryURL: dir)
        cache.save(sampleSnapshotRow(), ownerUserID: CacheTestIDs.ownerUserID)

        // Confirm it was saved.
        #expect(cache.load(ownerUserID: CacheTestIDs.ownerUserID) != nil)

        cache.clearAll()

        // After clearing the whole directory, load must return nil.
        #expect(cache.load(ownerUserID: CacheTestIDs.ownerUserID) == nil)
    }

    @Test func clearAllOnEmptyDirectoryIsNoOp() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheTest-\(UUID().uuidString)", isDirectory: true)
        // No defer removal — directory never created; this tests the guard path.

        let cache = FileDailyChallengeSnapshotCache(directoryURL: dir)
        // Must not throw or crash when the directory doesn't exist.
        cache.clearAll()

        let loaded = cache.load(ownerUserID: CacheTestIDs.ownerUserID)
        #expect(loaded == nil)
    }

    // MARK: Corrupt / wrong-version payload

    @Test func corruptDataOnDiskReturnsNil() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(
            CacheTestIDs.ownerUserID.uuidString.lowercased() + ".json"
        )
        try Data("not valid json {{{{".utf8).write(to: fileURL)

        let cache = FileDailyChallengeSnapshotCache(directoryURL: dir)

        // Must fail soft — return nil, not crash.
        let loaded = cache.load(ownerUserID: CacheTestIDs.ownerUserID)
        #expect(loaded == nil)
    }

    @Test func staleSchemaVersionOnDiskReturnsNil() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(
            CacheTestIDs.ownerUserID.uuidString.lowercased() + ".json"
        )
        // Write a valid JSON object with an obviously-wrong schema version.
        let stale = """
        {"schemaVersion": 99999, "ownerUserID": "\(CacheTestIDs.ownerUserID.uuidString)", "row": {}}
        """
        try Data(stale.utf8).write(to: fileURL)

        let cache = FileDailyChallengeSnapshotCache(directoryURL: dir)

        let loaded = cache.load(ownerUserID: CacheTestIDs.ownerUserID)
        #expect(loaded == nil)
    }

    // MARK: loadResult mapping

    @Test func loadResultProducesExpectedSnapshotAndStreak() throws {
        let row = sampleSnapshotRow(ownerUserID: CacheTestIDs.ownerUserID)
        let locale = Locale(identifier: "en_US")

        let result = row.loadResult(currentUserID: CacheTestIDs.ownerUserID, locale: locale)

        // Snapshot: one own question for the current user.
        #expect(result.snapshot.currentUserID == CacheTestIDs.ownerUserID)
        #expect(result.snapshot.ownQuestions.count == 1)
        // `DailyChallengeQuestion.prompt` is locale-resolved; with en_US it
        // matches `promptEN` from the raw row.
        #expect(result.snapshot.ownQuestions.first?.prompt == row.questions[0].promptEN)

        // Streak: pulled directly from the row's streak sub-row.
        #expect(result.streak.currentCount == 7)
        #expect(result.streak.longestCount == 12)
        #expect(result.streak.lastQualifiedDate == "2026-06-26")
    }

    @Test func loadResultWithNilStreakProducesNoneStreak() {
        var row = sampleSnapshotRow()
        // Simulate a row that the backend returned without a streak (new couple, no
        // challenge completed yet).
        row = DailyChallengeRemoteSnapshotRow(
            questions: row.questions,
            answerDetails: row.answerDetails,
            streak: nil,
            generatedAt: row.generatedAt
        )

        let result = row.loadResult(currentUserID: CacheTestIDs.ownerUserID)
        #expect(result.streak == .none)
    }
}

// MARK: - View-model seed tests

struct DailyChallengeViewModelSeedTests {

    // MARK: Seed on configure

    @MainActor
    @Test func configureSeederFromCacheBeforeNetworkReturns() async throws {
        // Arrange: pre-populate the in-memory cache with a row for the owner.
        let cache = InMemoryDailyChallengeSnapshotCache()
        let cachedRow = sampleSnapshotRow(ownerUserID: CacheTestIDs.ownerUserID)
        cache.save(cachedRow, ownerUserID: CacheTestIDs.ownerUserID)

        // The network service blocks until `loadProbe.release()` is called, so
        // we can observe the view model state between the cache seed and the
        // network return.
        let loadProbe = DailyChallengeViewModelSeedProbe()
        let networkSnapshot = makeSeedTestSnapshot(ownerUserID: CacheTestIDs.ownerUserID)
        let service = BlockingDailyChallengeService(
            snapshot: networkSnapshot,
            probe: loadProbe
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedSeedOperationProvider(),
            snapshotCache: cache
        )

        // Act: start configure but don't await it yet.
        let configureTask = Task { @MainActor in
            await viewModel.configure(currentUserID: CacheTestIDs.ownerUserID)
        }

        // Wait until the service's load has been called (the cache seed ran and
        // the network fetch is in flight).
        while await service.loadCount == 0 {
            await Task.yield()
        }

        // Assert: while the network is still blocked, the snapshot is already
        // seeded from the cache — not empty.
        #expect(viewModel.snapshot.ownQuestions.count == 1,
            "Expected cache-seeded question before network returns")
        #expect(viewModel.snapshot.currentUserID == CacheTestIDs.ownerUserID)

        // Release the network load and let configure finish.
        await loadProbe.release()
        await configureTask.value

        // After configure finishes, the network result should be applied.
        #expect(viewModel.snapshot.ownQuestions.count == networkSnapshot.ownQuestions.count)
        // The cache should have been written once (by the service after the
        // network call — via RecordingDailyChallengeService wiring in the live
        // path; here we verify the service was called at all).
        #expect(await service.loadCount == 1)
    }

    @MainActor
    @Test func networkResultReplacesTheCachedSeed() async throws {
        // Arrange: pre-populate the cache with a row that has 1 question.
        let cache = InMemoryDailyChallengeSnapshotCache()
        let cachedRow = sampleSnapshotRow(ownerUserID: CacheTestIDs.ownerUserID)
        cache.save(cachedRow, ownerUserID: CacheTestIDs.ownerUserID)

        // The network returns a snapshot with 3 questions (different from the
        // cached 1). After configure the view model must reflect the network
        // result, not the seed.
        let threeQuestionSnapshot = makeSeedTestSnapshot(
            ownerUserID: CacheTestIDs.ownerUserID,
            slotCount: 3
        )
        let service = ImmediateDailyChallengeService(snapshot: threeQuestionSnapshot)
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedSeedOperationProvider(),
            snapshotCache: cache
        )

        await viewModel.configure(currentUserID: CacheTestIDs.ownerUserID)

        // Network result (3 questions) wins over the cache seed (1 question).
        #expect(viewModel.snapshot.ownQuestions.count == 3)
    }

    @MainActor
    @Test func noCacheNilIsNoOpAndDoesNotBlockLoad() async throws {
        // When no cached row exists the configure path must proceed normally.
        let emptyCache = InMemoryDailyChallengeSnapshotCache()
        let networkSnapshot = makeSeedTestSnapshot(ownerUserID: CacheTestIDs.ownerUserID)
        let service = ImmediateDailyChallengeService(snapshot: networkSnapshot)
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedSeedOperationProvider(),
            snapshotCache: emptyCache
        )

        await viewModel.configure(currentUserID: CacheTestIDs.ownerUserID)

        // No crash, no empty-state weirdness — the network result is applied.
        #expect(viewModel.snapshot.ownQuestions.count == networkSnapshot.ownQuestions.count)
    }

    @MainActor
    @Test func differentUserGetsSeparateCacheAndDoesNotSeeCrossContent() async throws {
        // Save a row for ownerUserID. Then configure with otherUserID.
        let cache = InMemoryDailyChallengeSnapshotCache()
        let ownerRow = sampleSnapshotRow(ownerUserID: CacheTestIDs.ownerUserID)
        cache.save(ownerRow, ownerUserID: CacheTestIDs.ownerUserID)

        let service = ImmediateDailyChallengeService(
            snapshot: .empty(currentUserID: CacheTestIDs.otherUserID)
        )
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedSeedOperationProvider(),
            snapshotCache: cache
        )

        await viewModel.configure(currentUserID: CacheTestIDs.otherUserID)

        // The other user must not see the owner's cached content.
        #expect(viewModel.snapshot.currentUserID == CacheTestIDs.otherUserID)
        // Empty because the cache has no entry for otherUserID, and the service
        // returns an empty snapshot.
        #expect(viewModel.snapshot.ownQuestions.isEmpty)
    }

    // MARK: Home card loading stability

    /// Regression: the home card must not flash "no challenge" before the first
    /// load settles. Previously the empty initial snapshot rendered as `.noChallenge`
    /// on the first frame, then flipped to `.loading` once the reload set its in-flight
    /// flag, then back again — a visible loading → content → loading wobble. The card
    /// must show `.loading` from the first frame through the in-flight load, and only
    /// settle to `.noChallenge` once the load resolves.
    @MainActor
    @Test func homeCardShowsLoadingUntilFirstLoadResolves() async throws {
        let cache = InMemoryDailyChallengeSnapshotCache()
        let probe = DailyChallengeViewModelSeedProbe()
        let emptyNetwork = DailyChallengeSnapshot.empty(currentUserID: CacheTestIDs.ownerUserID)
        let service = BlockingDailyChallengeService(snapshot: emptyNetwork, probe: probe)
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedSeedOperationProvider(),
            snapshotCache: cache
        )

        // First frame, before configure runs: must be loading, not noChallenge.
        #expect(viewModel.homeCardState.kind == .loading)

        let configureTask = Task { @MainActor in
            await viewModel.configure(currentUserID: CacheTestIDs.ownerUserID)
        }
        while await service.loadCount == 0 {
            await Task.yield()
        }

        // While the (empty) network load is in flight: still loading, never a
        // premature noChallenge.
        #expect(viewModel.homeCardState.kind == .loading)

        await probe.release()
        await configureTask.value

        // Resolved now — an empty day settles to noChallenge exactly once.
        #expect(viewModel.homeCardState.kind == .noChallenge)
    }
}

// MARK: - Private test helpers

/// Builds a minimal snapshot with `slotCount` active questions seeded for
/// `ownerUserID`, for use in seed tests.
private func makeSeedTestSnapshot(
    ownerUserID: UUID,
    slotCount: Int = 1
) -> DailyChallengeSnapshot {
    let rows = (1...max(1, slotCount)).map { slot in
        DailyQuestionRow(
            coupleDayID: CacheTestIDs.coupleDay,
            coupleID: CacheTestIDs.coupleID,
            localDate: "2026-06-27",
            effectiveLocalDate: nil,
            startsAt: CacheTestIDs.startsAt,
            endsAt: CacheTestIDs.endsAt,
            instanceID: UUID(),
            seededForUserID: ownerUserID,
            slotNumber: slot,
            instanceStatus: "active",
            questionID: UUID(),
            questionVersionID: UUID(),
            questionKey: "small_moment_today",
            promptEN: "What small moment made you think of us today? [\(slot)]",
            shortPromptEN: "A small moment today",
            promptNB: "Prompt NB",
            shortPromptNB: "Short NB",
            answerKinds: [.text],
            ownAnswerID: nil,
            ownAnsweredAt: nil,
            partnerAnswerID: nil,
            partnerAnsweredAt: nil,
            canViewPartnerAnswer: false,
            isCurrentDay: true
        )
    }
    return DailyChallengeSnapshot.make(
        currentUserID: ownerUserID,
        rows: rows,
        answerDetails: [],
        locale: Locale(identifier: "en_US"),
        refreshedAt: CacheTestIDs.generatedAt
    )
}

/// A `DailyChallengeServicing` that blocks its `loadToday` until `release()` is
/// called, letting the test observe the view model's state between the cache seed
/// and the network return.
private actor BlockingDailyChallengeService: DailyChallengeServicing {
    private let snapshot: DailyChallengeSnapshot
    private let probe: DailyChallengeViewModelSeedProbe
    private(set) var loadCount = 0

    init(snapshot: DailyChallengeSnapshot, probe: DailyChallengeViewModelSeedProbe) {
        self.snapshot = snapshot
        self.probe = probe
    }

    func loadToday(currentUserID: UUID) async throws -> DailyChallengeLoadResult {
        loadCount += 1
        await probe.blockUntilReleased()
        return DailyChallengeLoadResult(snapshot: snapshot, streak: .none)
    }

    func startToday(currentUserID: UUID, operation _: SyncClientOperation) async throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: .empty(currentUserID: currentUserID), streak: .none)
    }

    func loadHistory(currentUserID _: UUID) async throws -> [DailyChallengeQuestion] { [] }

    func loadStreak() async throws -> CoupleStreak { .none }

    func editTextAnswer(instanceID _: UUID, text _: String, operation _: SyncClientOperation) async throws -> UUID {
        throw DailyChallengeServiceUnavailableError()
    }

    func editPartnerChoice(instanceID _: UUID, selectedUserID _: UUID, operation _: SyncClientOperation) async throws -> UUID {
        throw DailyChallengeServiceUnavailableError()
    }

    func shuffleQuestion(currentUserID: UUID, slotNumber _: Int, operation _: SyncClientOperation) async throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: .empty(currentUserID: currentUserID), streak: .none)
    }
}

/// A `DailyChallengeServicing` that returns immediately with a fixed snapshot.
private actor ImmediateDailyChallengeService: DailyChallengeServicing {
    private let snapshot: DailyChallengeSnapshot

    init(snapshot: DailyChallengeSnapshot) {
        self.snapshot = snapshot
    }

    func loadToday(currentUserID _: UUID) async throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: snapshot, streak: .none)
    }

    func startToday(currentUserID: UUID, operation _: SyncClientOperation) async throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: .empty(currentUserID: currentUserID), streak: .none)
    }

    func loadHistory(currentUserID _: UUID) async throws -> [DailyChallengeQuestion] { [] }

    func loadStreak() async throws -> CoupleStreak { .none }

    func editTextAnswer(instanceID _: UUID, text _: String, operation _: SyncClientOperation) async throws -> UUID {
        throw DailyChallengeServiceUnavailableError()
    }

    func editPartnerChoice(instanceID _: UUID, selectedUserID _: UUID, operation _: SyncClientOperation) async throws -> UUID {
        throw DailyChallengeServiceUnavailableError()
    }

    func shuffleQuestion(currentUserID: UUID, slotNumber _: Int, operation _: SyncClientOperation) async throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: .empty(currentUserID: currentUserID), streak: .none)
    }
}

/// Lets a test block `BlockingDailyChallengeService.loadToday` until `release()`
/// is explicitly called, enabling observation of the cache-seeded state while the
/// network is still in flight.
private actor DailyChallengeViewModelSeedProbe {
    private var released = false

    func blockUntilReleased() async {
        while !released {
            await Task.yield()
        }
    }

    func release() {
        released = true
    }
}

/// A minimal `SyncClientOperationProviding` for tests that don't exercise queuing.
@MainActor
private final class FixedSeedOperationProvider: SyncClientOperationProviding {
    func makeOperation() -> SyncClientOperation {
        SyncClientOperation(
            id: UUID(),
            clientID: UUID(),
            clientSequence: 1,
            localCreatedAt: CacheTestIDs.generatedAt
        )
    }
}
