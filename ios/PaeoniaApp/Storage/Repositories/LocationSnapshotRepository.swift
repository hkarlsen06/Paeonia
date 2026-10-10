import Foundation
import SwiftData

protocol LocationVisibilitySnapshotPersisting: Actor {
    func save(_ snapshot: LocationVisibilitySnapshot) async throws
    func load(ownerUserID: UUID, coupleID: UUID) async throws -> LocationVisibilitySnapshot?

    /// Stores a snapshot that came from the server. If the user made a sharing
    /// choice that the server has not confirmed, the local choice stays. The
    /// check and the write happen in one step, so a choice made at any point
    /// before the write is kept. Pass `true` when a sharing operation is still
    /// waiting in the outbox, which also covers a choice made before a relaunch.
    func saveRemote(
        _ snapshot: LocationVisibilitySnapshot,
        preservingLocalSharingChoiceIf hasPendingSharingOperation: Bool
    ) async throws

    /// Writes the viewer's sharing flag. With `isPendingConfirmation` the value
    /// counts as an unconfirmed local choice until `confirmViewerSharing` or a
    /// matching server value clears it. Pass `false` to put a value back after
    /// a failed save.
    func setViewerSharingEnabled(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date,
        isPendingConfirmation: Bool
    ) async throws

    /// Records the server's answer to a sharing operation. It changes nothing
    /// while a newer local choice is unconfirmed.
    func confirmViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date,
        otherChoicesPending: Bool
    ) async throws

    func delete(ownerUserID: UUID, coupleID: UUID) async throws
}

extension LocationVisibilitySnapshotPersisting {
    /// A new local sharing choice that the server has not confirmed yet.
    func setViewerSharingEnabled(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date
    ) async throws {
        try await setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: isEnabled,
            updatedAt: updatedAt,
            isPendingConfirmation: true
        )
    }
}

/// Sharing choices the user made on this phone that the server has not
/// confirmed. The SwiftData repositories share one instance because the map
/// screen and the live feed each create their own repository. The lock covers
/// the marker and the store write together, so a server value can never land
/// between a local choice and its marker.
// ponytail: kept in memory and keyed by owner and couple. A relaunch loses it,
// and the outbox check in the live feed covers that case.
nonisolated final class PendingSharingChoiceLedger: @unchecked Sendable {
    static let shared = PendingSharingChoiceLedger()

    private let lock = NSLock()
    private var choices: [String: Bool] = [:]

    func withChoices<T>(_ body: (inout [String: Bool]) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&choices)
    }
}

nonisolated extension LocationVisibilitySnapshot {
    /// Applies a server snapshot on top of an unconfirmed local sharing choice.
    /// Returns the snapshot to store and the choice that is still unconfirmed.
    func mergingRemote(
        local: LocationVisibilitySnapshot?,
        pendingChoice: Bool?,
        hasPendingSharingOperation: Bool
    ) -> (snapshot: LocationVisibilitySnapshot, pendingChoice: Bool?) {
        let choice = pendingChoice ?? (hasPendingSharingOperation ? local?.viewerSharingEnabled : nil)
        guard let choice else {
            return (self, nil)
        }
        if viewerSharingEnabled == choice {
            return (self, hasPendingSharingOperation ? choice : nil)
        }

        let state: PartnerLocationVisibilityState
        if !choice {
            state = .disabled
        } else if visibilityState == .disabled {
            state = .unknown("local")
        } else {
            state = visibilityState
        }
        let merged = LocationVisibilitySnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            viewerUserID: viewerUserID,
            partnerUserID: partnerUserID,
            visibilityState: state,
            viewerSharingEnabled: choice,
            partnerSharingEnabled: partnerSharingEnabled,
            partnerLocation: partnerLocation,
            partnerLocationIsStale: partnerLocationIsStale,
            updatedAt: updatedAt,
            refreshedAt: refreshedAt
        )
        return (merged, choice)
    }
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
    private let ledger: PendingSharingChoiceLedger

    init(container: ModelContainer, ledger: PendingSharingChoiceLedger = .shared) {
        self.container = container
        self.ledger = ledger
    }

    func save(_ snapshot: LocationVisibilitySnapshot) async throws {
        let context = ModelContext(container)
        if let existing = try fetch(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID, in: context) {
            existing.update(from: snapshot)
        } else {
            context.insert(LocalLocationVisibilitySnapshot(snapshot: snapshot))
        }
        try context.save()
        LocalStoreChanges.post(.locationVisibility, ownerUserID: snapshot.ownerUserID)
    }

    func saveRemote(
        _ snapshot: LocationVisibilitySnapshot,
        preservingLocalSharingChoiceIf hasPendingSharingOperation: Bool
    ) async throws {
        let key = LocalLocationVisibilitySnapshot.storageKey(
            ownerUserID: snapshot.ownerUserID,
            coupleID: snapshot.coupleID
        )
        // No await between the read and the write, and the lock keeps other
        // repositories on the same store out of the way.
        try ledger.withChoices { choices in
            let context = ModelContext(container)
            let existing = try fetch(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID, in: context)
            let merged = snapshot.mergingRemote(
                local: existing?.snapshot,
                pendingChoice: choices[key],
                hasPendingSharingOperation: hasPendingSharingOperation
            )
            if let existing {
                existing.update(from: merged.snapshot)
            } else {
                context.insert(LocalLocationVisibilitySnapshot(snapshot: merged.snapshot))
            }
            try context.save()
            choices[key] = merged.pendingChoice
        }
        LocalStoreChanges.post(.locationVisibility, ownerUserID: snapshot.ownerUserID)
    }

    func load(ownerUserID: UUID, coupleID: UUID) async throws -> LocationVisibilitySnapshot? {
        let context = ModelContext(container)
        return try fetch(ownerUserID: ownerUserID, coupleID: coupleID, in: context)?.snapshot
    }

    func setViewerSharingEnabled(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date,
        isPendingConfirmation: Bool
    ) async throws {
        let key = LocalLocationVisibilitySnapshot.storageKey(ownerUserID: ownerUserID, coupleID: coupleID)
        try ledger.withChoices { choices in
            try applyViewerSharing(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                isEnabled: isEnabled,
                updatedAt: updatedAt
            )
            choices[key] = isPendingConfirmation ? isEnabled : nil
        }
        LocalStoreChanges.post(.locationVisibility, ownerUserID: ownerUserID)
    }

    func confirmViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date,
        otherChoicesPending: Bool
    ) async throws {
        let key = LocalLocationVisibilitySnapshot.storageKey(ownerUserID: ownerUserID, coupleID: coupleID)
        let applied = try ledger.withChoices { choices -> Bool in
            if otherChoicesPending || choices[key].map({ $0 != isEnabled }) == true {
                return false
            }
            try applyViewerSharing(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                isEnabled: isEnabled,
                updatedAt: updatedAt
            )
            choices[key] = nil
            return true
        }
        if applied {
            LocalStoreChanges.post(.locationVisibility, ownerUserID: ownerUserID)
        }
    }

    private func applyViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date
    ) throws {
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
        let key = LocalLocationVisibilitySnapshot.storageKey(ownerUserID: ownerUserID, coupleID: coupleID)
        let deleted = try ledger.withChoices { choices -> Bool in
            choices[key] = nil
            let context = ModelContext(container)
            guard let existing = try fetch(ownerUserID: ownerUserID, coupleID: coupleID, in: context) else {
                return false
            }
            context.delete(existing)
            try context.save()
            return true
        }
        if deleted {
            LocalStoreChanges.post(.locationVisibility, ownerUserID: ownerUserID)
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
        LocalStoreChanges.post(.ownLocation, ownerUserID: snapshot.ownerUserID)
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
        LocalStoreChanges.post(.ownLocation, ownerUserID: ownerUserID)
    }

    func delete(ownerUserID: UUID, coupleID: UUID) async throws {
        let context = ModelContext(container)
        if let existing = try fetch(ownerUserID: ownerUserID, coupleID: coupleID, in: context) {
            context.delete(existing)
            try context.save()
            LocalStoreChanges.post(.ownLocation, ownerUserID: ownerUserID)
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
    private var pendingChoices: [String: Bool] = [:]

    func save(_ snapshot: LocationVisibilitySnapshot) async throws {
        snapshots[key(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID)] = snapshot
        LocalStoreChanges.post(.locationVisibility, ownerUserID: snapshot.ownerUserID)
    }

    func saveRemote(
        _ snapshot: LocationVisibilitySnapshot,
        preservingLocalSharingChoiceIf hasPendingSharingOperation: Bool
    ) async throws {
        let snapshotKey = key(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID)
        let merged = snapshot.mergingRemote(
            local: snapshots[snapshotKey],
            pendingChoice: pendingChoices[snapshotKey],
            hasPendingSharingOperation: hasPendingSharingOperation
        )
        snapshots[snapshotKey] = merged.snapshot
        pendingChoices[snapshotKey] = merged.pendingChoice
        LocalStoreChanges.post(.locationVisibility, ownerUserID: snapshot.ownerUserID)
    }

    func load(ownerUserID: UUID, coupleID: UUID) async throws -> LocationVisibilitySnapshot? {
        snapshots[key(ownerUserID: ownerUserID, coupleID: coupleID)]
    }

    func setViewerSharingEnabled(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date,
        isPendingConfirmation: Bool
    ) async throws {
        applyViewerSharing(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: isEnabled,
            updatedAt: updatedAt
        )
        pendingChoices[key(ownerUserID: ownerUserID, coupleID: coupleID)] = isPendingConfirmation ? isEnabled : nil
        LocalStoreChanges.post(.locationVisibility, ownerUserID: ownerUserID)
    }

    func confirmViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date,
        otherChoicesPending: Bool
    ) async throws {
        let snapshotKey = key(ownerUserID: ownerUserID, coupleID: coupleID)
        if otherChoicesPending || pendingChoices[snapshotKey].map({ $0 != isEnabled }) == true {
            return
        }
        applyViewerSharing(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: isEnabled,
            updatedAt: updatedAt
        )
        pendingChoices[snapshotKey] = nil
        LocalStoreChanges.post(.locationVisibility, ownerUserID: ownerUserID)
    }

    private func applyViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date
    ) {
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
        pendingChoices[key(ownerUserID: ownerUserID, coupleID: coupleID)] = nil
        LocalStoreChanges.post(.locationVisibility, ownerUserID: ownerUserID)
    }

    private func key(ownerUserID: UUID, coupleID: UUID) -> String {
        LocalLocationVisibilitySnapshot.storageKey(ownerUserID: ownerUserID, coupleID: coupleID)
    }
}

actor InMemoryOwnLocationSnapshotRepository: OwnLocationSnapshotPersisting {
    private var snapshots: [String: OwnLocationSnapshot] = [:]

    func save(_ snapshot: OwnLocationSnapshot) async throws {
        snapshots[key(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID)] = snapshot
        LocalStoreChanges.post(.ownLocation, ownerUserID: snapshot.ownerUserID)
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
        LocalStoreChanges.post(.ownLocation, ownerUserID: ownerUserID)
    }

    func delete(ownerUserID: UUID, coupleID: UUID) async throws {
        snapshots[key(ownerUserID: ownerUserID, coupleID: coupleID)] = nil
        LocalStoreChanges.post(.ownLocation, ownerUserID: ownerUserID)
    }

    private func key(ownerUserID: UUID, coupleID: UUID) -> String {
        LocalOwnLocationSnapshot.storageKey(ownerUserID: ownerUserID, coupleID: coupleID)
    }
}
