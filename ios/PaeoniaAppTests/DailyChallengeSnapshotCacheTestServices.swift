import Foundation
@testable import PaeoniaApp

/// A `DailyChallengeServicing` that blocks its `loadToday` until `release()` is
/// called, letting the test observe the view model's state between the cache seed
/// and the network return.
actor BlockingDailyChallengeService: DailyChallengeServicing {
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

    func startToday(currentUserID: UUID, operation _: SyncClientOperation) throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: .empty(currentUserID: currentUserID), streak: .none)
    }

    func loadHistory(currentUserID _: UUID) throws -> [DailyChallengeQuestion] { [] }

    func loadStreak() throws -> CoupleStreak { .none }

    func editTextAnswer(instanceID _: UUID, text _: String, operation _: SyncClientOperation) throws -> UUID {
        throw DailyChallengeServiceUnavailableError()
    }

    func editPartnerChoice(
        instanceID _: UUID,
        selectedUserID _: UUID,
        operation _: SyncClientOperation
    ) throws -> UUID {
        throw DailyChallengeServiceUnavailableError()
    }

    func shuffleQuestion(
        currentUserID: UUID,
        slotNumber _: Int,
        operation _: SyncClientOperation
    ) throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: .empty(currentUserID: currentUserID), streak: .none)
    }
}

/// A `DailyChallengeServicing` that returns immediately with a fixed snapshot.
actor ImmediateDailyChallengeService: DailyChallengeServicing {
    private let snapshot: DailyChallengeSnapshot

    init(snapshot: DailyChallengeSnapshot) {
        self.snapshot = snapshot
    }

    func loadToday(currentUserID _: UUID) throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: snapshot, streak: .none)
    }

    func startToday(currentUserID: UUID, operation _: SyncClientOperation) throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: .empty(currentUserID: currentUserID), streak: .none)
    }

    func loadHistory(currentUserID _: UUID) throws -> [DailyChallengeQuestion] { [] }

    func loadStreak() throws -> CoupleStreak { .none }

    func editTextAnswer(instanceID _: UUID, text _: String, operation _: SyncClientOperation) throws -> UUID {
        throw DailyChallengeServiceUnavailableError()
    }

    func editPartnerChoice(
        instanceID _: UUID,
        selectedUserID _: UUID,
        operation _: SyncClientOperation
    ) throws -> UUID {
        throw DailyChallengeServiceUnavailableError()
    }

    func shuffleQuestion(
        currentUserID: UUID,
        slotNumber _: Int,
        operation _: SyncClientOperation
    ) throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: .empty(currentUserID: currentUserID), streak: .none)
    }
}

/// Lets a test block `BlockingDailyChallengeService.loadToday` until `release()`
/// is explicitly called, enabling observation of the cache-seeded state while the
/// network is still in flight.
actor DailyChallengeViewModelSeedProbe {
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
