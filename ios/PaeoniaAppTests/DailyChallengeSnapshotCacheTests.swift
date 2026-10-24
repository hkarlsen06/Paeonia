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
    /// Far in the future, so the view model (which drops a day once its end passes)
    /// never treats the cached fixture day as ended.
    static let endsAt = Date(timeIntervalSince1970: 4_102_444_800)
    static let generatedAt = Date(timeIntervalSince1970: 1_782_450_000)
    static let answerDate = Date(timeIntervalSince1970: 1_782_455_000)
}

/// Builds a minimal `DailyChallengeRemoteSnapshotRow` with one question and one
/// answer for use across multiple cache tests.
private func sampleSnapshotRow() -> DailyChallengeRemoteSnapshotRow {
    let questionRow = DailyQuestionRow(
        coupleDayID: CacheTestIDs.coupleDay,
        coupleID: CacheTestIDs.coupleID,
        localDate: "2026-06-27",
        effectiveLocalDate: nil,
        startsAt: CacheTestIDs.startsAt,
        endsAt: CacheTestIDs.endsAt,
        instanceID: fixedUUID("eeee0000-0000-0000-0000-000000000000"),
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
    @Test func loadForDifferentOwnerReturnsNil() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = FileDailyChallengeSnapshotCache(directoryURL: dir)
        let row = sampleSnapshotRow()

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
}

// MARK: - View-model seed tests

struct DailyChallengeViewModelSeedTests {
    @MainActor
    @Test func configureSeederFromCacheBeforeNetworkReturns() async throws {
        let cache = InMemoryDailyChallengeSnapshotCache()
        let cachedRow = sampleSnapshotRow()
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

        let configureTask = Task { @MainActor in
            await viewModel.configure(currentUserID: CacheTestIDs.ownerUserID)
        }

        // Wait until the service's load has been called (the cache seed ran and
        // the network fetch is in flight).
        while await service.loadCount == 0 {
            await Task.yield()
        }

        #expect(viewModel.snapshot.todayQuestion != nil,
            "Expected cache-seeded question before network returns")
        #expect(viewModel.snapshot.currentUserID == CacheTestIDs.ownerUserID)

        // Release the network load and let configure finish.
        await loadProbe.release()
        await configureTask.value

        // After configure finishes, the network result should be applied.
        #expect(viewModel.snapshot.todayQuestion?.id == networkSnapshot.todayQuestion?.id)
        // The cache should have been written once (by the service after the
        // network call — via RecordingDailyChallengeService wiring in the live
        // path; here we verify the service was called at all).
        #expect(await service.loadCount == 1)
    }

    @MainActor
    @Test func differentUserGetsSeparateCacheAndDoesNotSeeCrossContent() async throws {
        // Save a row for ownerUserID. Then configure with otherUserID.
        let cache = InMemoryDailyChallengeSnapshotCache()
        let ownerRow = sampleSnapshotRow()
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
        #expect(!viewModel.snapshot.hasAnyQuestions)
    }
}

// MARK: - Private test helpers

/// Builds a minimal snapshot with today's question for `ownerUserID`, for use in
/// seed tests.
private func makeSeedTestSnapshot(ownerUserID: UUID) -> DailyChallengeSnapshot {
    let row = DailyQuestionRow(
        coupleDayID: CacheTestIDs.coupleDay,
        coupleID: CacheTestIDs.coupleID,
        localDate: "2026-06-27",
        effectiveLocalDate: nil,
        startsAt: CacheTestIDs.startsAt,
        endsAt: CacheTestIDs.endsAt,
        instanceID: UUID(),
        instanceStatus: "active",
        questionID: UUID(),
        questionVersionID: UUID(),
        questionKey: "small_moment_today",
        promptEN: "What small moment made you think of us today?",
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
    return DailyChallengeSnapshot.make(
        currentUserID: ownerUserID,
        rows: [row],
        answerDetails: [],
        locale: Locale(identifier: "en_US"),
        refreshedAt: CacheTestIDs.generatedAt
    )
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
