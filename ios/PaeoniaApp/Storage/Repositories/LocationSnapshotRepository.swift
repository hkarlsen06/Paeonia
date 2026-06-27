import Foundation
import SwiftData

protocol LocationVisibilitySnapshotPersisting: Actor {
    func save(_ snapshot: LocationVisibilitySnapshot) async throws
    func load(ownerUserID: UUID, coupleID: UUID) async throws -> LocationVisibilitySnapshot?
    func setViewerSharingEnabled(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date
    ) async throws
    func delete(ownerUserID: UUID, coupleID: UUID) async throws
}

protocol OwnLocationSnapshotPersisting: Actor {
    func save(_ snapshot: OwnLocationSnapshot) async throws
    func load(ownerUserID: UUID, coupleID: UUID) async throws -> OwnLocationSnapshot?
    func clearPendingOperation(
        ownerUserID: UUID,
        coupleID: UUID,
        operationID: UUID
    ) async throws
    func delete(ownerUserID: UUID, coupleID: UUID) async throws
}

actor SwiftDataLocationVisibilitySnapshotRepository: LocationVisibilitySnapshotPersisting {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func save(_ snapshot: LocationVisibilitySnapshot) async throws {
        let context = ModelContext(container)
        if let existing = try fetch(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID, in: context) {
            existing.update(from: snapshot)
        } else {
            context.insert(LocalLocationVisibilitySnapshot(snapshot: snapshot))
        }
        try context.save()
    }

    func load(ownerUserID: UUID, coupleID: UUID) async throws -> LocationVisibilitySnapshot? {
        let context = ModelContext(container)
        return try fetch(ownerUserID: ownerUserID, coupleID: coupleID, in: context)?.snapshot
    }

    func setViewerSharingEnabled(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date
    ) async throws {
        let context = ModelContext(container)
        if let existing = try fetch(ownerUserID: ownerUserID, coupleID: coupleID, in: context) {
            existing.viewerSharingEnabled = isEnabled
            if isEnabled, existing.visibilityStateRawValue == PartnerLocationVisibilityState.disabled.rawValue {
                existing.visibilityStateRawValue = PartnerLocationVisibilityState.unknown("local").rawValue
            } else if !isEnabled {
                existing.visibilityStateRawValue = PartnerLocationVisibilityState.disabled.rawValue
            }
            existing.updatedAt = updatedAt
            existing.refreshedAt = updatedAt
        } else {
            context.insert(
                LocalLocationVisibilitySnapshot(
                    snapshot: LocationVisibilitySnapshot(
                        ownerUserID: ownerUserID,
                        coupleID: coupleID,
                        viewerUserID: ownerUserID,
                        partnerUserID: nil,
                        visibilityState: isEnabled ? .unknown("local") : .disabled,
                        viewerSharingEnabled: isEnabled,
                        partnerSharingEnabled: false,
                        partnerLocation: nil,
                        partnerLocationIsStale: false,
                        updatedAt: updatedAt,
                        refreshedAt: updatedAt
                    )
                )
            )
        }
        try context.save()
    }

    func delete(ownerUserID: UUID, coupleID: UUID) async throws {
        let context = ModelContext(container)
        if let existing = try fetch(ownerUserID: ownerUserID, coupleID: coupleID, in: context) {
            context.delete(existing)
            try context.save()
        }
    }

    private func fetch(
        ownerUserID: UUID,
        coupleID: UUID,
        in context: ModelContext
    ) throws -> LocalLocationVisibilitySnapshot? {
        let storageKey = LocalLocationVisibilitySnapshot.storageKey(
            ownerUserID: ownerUserID,
            coupleID: coupleID
        )
        var descriptor = FetchDescriptor<LocalLocationVisibilitySnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.storageKey == storageKey
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

actor SwiftDataOwnLocationSnapshotRepository: OwnLocationSnapshotPersisting {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func save(_ snapshot: OwnLocationSnapshot) async throws {
        let context = ModelContext(container)
        if let existing = try fetch(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID, in: context) {
            existing.update(from: snapshot)
        } else {
            context.insert(LocalOwnLocationSnapshot(snapshot: snapshot))
        }
        try context.save()
    }

    func load(ownerUserID: UUID, coupleID: UUID) async throws -> OwnLocationSnapshot? {
        let context = ModelContext(container)
        return try fetch(ownerUserID: ownerUserID, coupleID: coupleID, in: context)?.snapshot
    }

    func clearPendingOperation(
        ownerUserID: UUID,
        coupleID: UUID,
        operationID: UUID
    ) async throws {
        let context = ModelContext(container)
        guard let existing = try fetch(ownerUserID: ownerUserID, coupleID: coupleID, in: context),
              existing.pendingOperationID == operationID
        else {
            return
        }
        existing.pendingOperationID = nil
        existing.updatedAt = Date()
        try context.save()
    }

    func delete(ownerUserID: UUID, coupleID: UUID) async throws {
        let context = ModelContext(container)
        if let existing = try fetch(ownerUserID: ownerUserID, coupleID: coupleID, in: context) {
            context.delete(existing)
            try context.save()
        }
    }

    private func fetch(
        ownerUserID: UUID,
        coupleID: UUID,
        in context: ModelContext
    ) throws -> LocalOwnLocationSnapshot? {
        let storageKey = LocalOwnLocationSnapshot.storageKey(ownerUserID: ownerUserID, coupleID: coupleID)
        var descriptor = FetchDescriptor<LocalOwnLocationSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.storageKey == storageKey
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

actor InMemoryLocationVisibilitySnapshotRepository: LocationVisibilitySnapshotPersisting {
    private var snapshots: [String: LocationVisibilitySnapshot] = [:]

    func save(_ snapshot: LocationVisibilitySnapshot) async throws {
        snapshots[key(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID)] = snapshot
    }

    func load(ownerUserID: UUID, coupleID: UUID) async throws -> LocationVisibilitySnapshot? {
        snapshots[key(ownerUserID: ownerUserID, coupleID: coupleID)]
    }

    func setViewerSharingEnabled(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date
    ) async throws {
        let existing = snapshots[key(ownerUserID: ownerUserID, coupleID: coupleID)]
        let nextState: PartnerLocationVisibilityState
        if !isEnabled {
            nextState = .disabled
        } else if existing?.visibilityState == .disabled {
            nextState = .unknown("local")
        } else {
            nextState = existing?.visibilityState ?? .unknown("local")
        }
        snapshots[key(ownerUserID: ownerUserID, coupleID: coupleID)] = LocationVisibilitySnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            viewerUserID: existing?.viewerUserID ?? ownerUserID,
            partnerUserID: existing?.partnerUserID,
            visibilityState: nextState,
            viewerSharingEnabled: isEnabled,
            partnerSharingEnabled: existing?.partnerSharingEnabled ?? false,
            partnerLocation: existing?.partnerLocation,
            partnerLocationIsStale: existing?.partnerLocationIsStale ?? false,
            updatedAt: updatedAt,
            refreshedAt: updatedAt
        )
    }

    func delete(ownerUserID: UUID, coupleID: UUID) async throws {
        snapshots[key(ownerUserID: ownerUserID, coupleID: coupleID)] = nil
    }

    private func key(ownerUserID: UUID, coupleID: UUID) -> String {
        LocalLocationVisibilitySnapshot.storageKey(ownerUserID: ownerUserID, coupleID: coupleID)
    }
}

actor InMemoryOwnLocationSnapshotRepository: OwnLocationSnapshotPersisting {
    private var snapshots: [String: OwnLocationSnapshot] = [:]

    func save(_ snapshot: OwnLocationSnapshot) async throws {
        snapshots[key(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID)] = snapshot
    }

    func load(ownerUserID: UUID, coupleID: UUID) async throws -> OwnLocationSnapshot? {
        snapshots[key(ownerUserID: ownerUserID, coupleID: coupleID)]
    }

    func clearPendingOperation(
        ownerUserID: UUID,
        coupleID: UUID,
        operationID: UUID
    ) async throws {
        let snapshotKey = key(ownerUserID: ownerUserID, coupleID: coupleID)
        guard let existing = snapshots[snapshotKey], existing.pendingOperationID == operationID else {
            return
        }
        snapshots[snapshotKey] = OwnLocationSnapshot(
            ownerUserID: existing.ownerUserID,
            coupleID: existing.coupleID,
            location: existing.location,
            source: existing.source,
            pendingOperationID: nil,
            updatedAt: Date()
        )
    }

    func delete(ownerUserID: UUID, coupleID: UUID) async throws {
        snapshots[key(ownerUserID: ownerUserID, coupleID: coupleID)] = nil
    }

    private func key(ownerUserID: UUID, coupleID: UUID) -> String {
        LocalOwnLocationSnapshot.storageKey(ownerUserID: ownerUserID, coupleID: coupleID)
    }
}
