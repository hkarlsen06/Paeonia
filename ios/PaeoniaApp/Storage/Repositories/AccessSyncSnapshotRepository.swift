import Foundation
import SwiftData

nonisolated struct AccessSyncSnapshot: Equatable, Sendable {
    let ownerUserID: UUID
    let userEntitlement: SupabaseUserEntitlement?
    let coupleEntitlement: SupabaseCoupleEntitlement?
    let relationshipState: SupabaseRelationshipState?
    let refreshedAt: Date

    init(
        ownerUserID: UUID,
        userEntitlement: SupabaseUserEntitlement?,
        coupleEntitlement: SupabaseCoupleEntitlement?,
        relationshipState: SupabaseRelationshipState?,
        refreshedAt: Date = Date()
    ) {
        self.ownerUserID = ownerUserID
        self.userEntitlement = userEntitlement
        self.coupleEntitlement = coupleEntitlement
        self.relationshipState = relationshipState
        self.refreshedAt = refreshedAt
    }
}

protocol AccessSyncSnapshotPersisting: Actor {
    func save(_ snapshot: AccessSyncSnapshot) async throws
    func load(ownerUserID: UUID) async throws -> AccessSyncSnapshot?
    func delete(ownerUserID: UUID) async throws
}

extension AccessSyncSnapshotPersisting {
    func replaceRelationshipStartedOn(
        ownerUserID: UUID,
        startedOn: String,
        refreshedAt: Date
    ) async throws {
        guard let existing = try await load(ownerUserID: ownerUserID),
              let relationshipState = existing.relationshipState
        else {
            return
        }

        try await save(
            AccessSyncSnapshot(
                ownerUserID: ownerUserID,
                userEntitlement: existing.userEntitlement,
                coupleEntitlement: existing.coupleEntitlement,
                relationshipState: relationshipState.replacingStartedOn(startedOn),
                refreshedAt: refreshedAt
            )
        )
    }
}

actor SwiftDataAccessSyncSnapshotRepository: AccessSyncSnapshotPersisting {
    private let container: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        self.container = container
    }

    func save(_ snapshot: AccessSyncSnapshot) async throws {
        let context = ModelContext(container)
        let localSnapshot: LocalAccessSyncSnapshot

        if let existingSnapshot = try fetchSnapshot(ownerUserID: snapshot.ownerUserID, in: context) {
            localSnapshot = existingSnapshot
        } else {
            localSnapshot = LocalAccessSyncSnapshot(ownerUserID: snapshot.ownerUserID)
            context.insert(localSnapshot)
        }

        localSnapshot.userEntitlementData = try encode(snapshot.userEntitlement)
        localSnapshot.coupleEntitlementData = try encode(snapshot.coupleEntitlement)
        localSnapshot.relationshipStateData = try encode(snapshot.relationshipState)
        localSnapshot.refreshedAt = snapshot.refreshedAt

        try context.save()
    }

    func load(ownerUserID: UUID) async throws -> AccessSyncSnapshot? {
        let context = ModelContext(container)

        guard let snapshot = try fetchSnapshot(ownerUserID: ownerUserID, in: context) else {
            return nil
        }

        return AccessSyncSnapshot(
            ownerUserID: snapshot.ownerUserID,
            userEntitlement: try decode(
                SupabaseUserEntitlement.self,
                from: snapshot.userEntitlementData
            ),
            coupleEntitlement: try decode(
                SupabaseCoupleEntitlement.self,
                from: snapshot.coupleEntitlementData
            ),
            relationshipState: try decode(
                SupabaseRelationshipState.self,
                from: snapshot.relationshipStateData
            ),
            refreshedAt: snapshot.refreshedAt
        )
    }

    func delete(ownerUserID: UUID) async throws {
        let context = ModelContext(container)

        if let snapshot = try fetchSnapshot(ownerUserID: ownerUserID, in: context) {
            context.delete(snapshot)
            try context.save()
        }
    }

    private func fetchSnapshot(
        ownerUserID: UUID,
        in context: ModelContext
    ) throws -> LocalAccessSyncSnapshot? {
        var descriptor = FetchDescriptor<LocalAccessSyncSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.ownerUserID == ownerUserID
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func encode<Value: Encodable>(_ value: Value?) throws -> Data? {
        guard let value else {
            return nil
        }

        return try encoder.encode(value)
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data?
    ) throws -> Value? {
        guard let data else {
            return nil
        }

        return try decoder.decode(type, from: data)
    }
}

actor InMemoryAccessSyncSnapshotRepository: AccessSyncSnapshotPersisting {
    private var snapshots: [UUID: AccessSyncSnapshot] = [:]

    func save(_ snapshot: AccessSyncSnapshot) async throws {
        snapshots[snapshot.ownerUserID] = snapshot
    }

    func load(ownerUserID: UUID) async throws -> AccessSyncSnapshot? {
        snapshots[ownerUserID]
    }

    func delete(ownerUserID: UUID) async throws {
        snapshots[ownerUserID] = nil
    }
}
