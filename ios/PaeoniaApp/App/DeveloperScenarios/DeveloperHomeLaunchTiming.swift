#if DEBUG
import Foundation

/// Delays independent Home reads while keeping the production root and local stores.
struct DeveloperHomeLaunchTiming {
    let location: Duration
    let question: Duration
    let calendar: Duration

    static let locationFirst = Self(location: .seconds(0.7), question: .seconds(1.6), calendar: .seconds(2.3))
    static let calendarFirst = Self(location: .seconds(2.3), question: .seconds(1.6), calendar: .seconds(0.7))

    func seedMap(
        visibility: InMemoryLocationVisibilityRepository,
        ownLocation: InMemoryOwnLocationSnapshotRepository
    ) async throws {
        let owner = DeveloperScenarioFixture.currentUserID
        let couple = DeveloperScenarioFixture.coupleID
        let now = Date()
        try await ownLocation.save(OwnLocationSnapshot(
            ownerUserID: owner, coupleID: couple,
            location: LocationPoint(latitude: 59.9139, longitude: 10.7522, capturedAt: now),
            source: .foregroundOpen, pendingOperationID: nil, updatedAt: now
        ))
        try await visibility.save(LocationVisibilitySnapshot(
            ownerUserID: owner, coupleID: couple, viewerUserID: owner,
            partnerUserID: DeveloperScenarioFixture.partnerUserID,
            visibilityState: .visible, viewerSharingEnabled: true, partnerSharingEnabled: true,
            partnerLocation: LocationPoint(latitude: 59.94, longitude: 10.79, capturedAt: now),
            partnerLocationIsStale: false, updatedAt: now, refreshedAt: now
        ))
    }
}

actor DeveloperDelayedStartedOnService {
    let base: any RelationshipStartedOnDataServicing
    let delay: Duration

    init(base: any RelationshipStartedOnDataServicing, delay: Duration) {
        self.base = base
        self.delay = delay
    }
}

extension DeveloperDelayedStartedOnService: RelationshipStartedOnDataServicing {
    func loadStartedOn(ownerUserID: UUID) async throws -> RelationshipStartedOnLocalState {
        try await Task.sleep(for: delay)
        return try await base.loadStartedOn(ownerUserID: ownerUserID)
    }

    func setStartedOn(_ startedOn: PairingStartDate, ownerUserID: UUID, operation: SyncClientOperation) async throws {
        try await base.setStartedOn(startedOn, ownerUserID: ownerUserID, operation: operation)
    }
}
#endif
