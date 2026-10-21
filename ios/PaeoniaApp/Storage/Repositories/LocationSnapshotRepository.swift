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

    /// Writes the viewer's sharing flag and pause. With `isPendingConfirmation`
    /// the value counts as an unconfirmed local choice until `confirmViewerSharing`
    /// or a matching server value clears it. Pass `false` to put a value back after
    /// a failed save.
    func setViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        choice: ViewerSharingChoice,
        updatedAt: Date,
        isPendingConfirmation: Bool
    ) async throws

    /// Records the server's answer to a sharing operation. It changes nothing while
    /// a newer local choice than the one the operation sent is unconfirmed.
    func confirmViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        confirmation: ViewerSharingConfirmation,
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
        pausedUntil: Date? = nil,
        updatedAt: Date
    ) async throws {
        try await setViewerSharing(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            choice: ViewerSharingChoice(isEnabled: isEnabled, pausedUntil: pausedUntil),
            updatedAt: updatedAt,
            isPendingConfirmation: true
        )
    }

    func setViewerSharingEnabled(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date,
        isPendingConfirmation: Bool
    ) async throws {
        try await setViewerSharing(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            choice: ViewerSharingChoice(isEnabled: isEnabled),
            updatedAt: updatedAt,
            isPendingConfirmation: isPendingConfirmation
        )
    }

    /// A confirmation where the server kept the choice as it was sent.
    func confirmViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        choice: ViewerSharingChoice,
        updatedAt: Date,
        otherChoicesPending: Bool
    ) async throws {
        try await confirmViewerSharing(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            confirmation: ViewerSharingConfirmation(choice),
            updatedAt: updatedAt,
            otherChoicesPending: otherChoicesPending
        )
    }

    func confirmViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date,
        otherChoicesPending: Bool
    ) async throws {
        try await confirmViewerSharing(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            choice: ViewerSharingChoice(isEnabled: isEnabled),
            updatedAt: updatedAt,
            otherChoicesPending: otherChoicesPending
        )
    }
}

// ponytail: kept in memory and keyed by owner and couple. A relaunch loses it,
// and the outbox check in the live feed covers that case.
/// Sharing choices the user made on this phone that the server has not
/// confirmed. The SwiftData repositories share one instance because the map
/// screen and the live feed each create their own repository. The lock covers
/// the marker and the store write together, so a server value can never land
/// between a local choice and its marker.
nonisolated final class PendingSharingChoiceLedger: @unchecked Sendable {
    static let shared = PendingSharingChoiceLedger()

    private let lock = NSLock()
    private var choices: [String: ViewerSharingChoice] = [:]

    func withChoices<T>(_ body: (inout [String: ViewerSharingChoice]) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&choices)
    }

    /// Forgets every unconfirmed choice of one user. A privacy purge deletes the
    /// rows these choices describe; a leftover entry could otherwise override
    /// the server's answer after the next sign-in in the same app session.
    func removeChoices(ownerUserID: UUID) {
        let prefix = ownerUserID.uuidString.lowercased() + ":"
        withChoices { choices in
            choices = choices.filter { !$0.key.hasPrefix(prefix) }
        }
    }
}

nonisolated extension LocationVisibilitySnapshot {
    /// Applies a server snapshot on top of an unconfirmed local sharing choice.
    /// Returns the snapshot to store and the choice that is still unconfirmed.
    func mergingRemote(
        local: LocationVisibilitySnapshot?,
        pendingChoice: ViewerSharingChoice?,
        hasPendingSharingOperation: Bool
    ) -> (snapshot: LocationVisibilitySnapshot, pendingChoice: ViewerSharingChoice?) {
        let localChoice = local.map {
            ViewerSharingChoice(isEnabled: $0.viewerSharingEnabled, pausedUntil: $0.viewerPausedUntil)
        }
        let choice = pendingChoice ?? (hasPendingSharingOperation ? localChoice : nil)
        guard let choice else {
            return (self, nil)
        }
        let remoteChoice = ViewerSharingChoice(isEnabled: viewerSharingEnabled, pausedUntil: viewerPausedUntil)
        if remoteChoice == choice {
            return (self, hasPendingSharingOperation ? choice : nil)
        }

        let state: PartnerLocationVisibilityState
        if !choice.isEnabled {
            state = .disabled
        } else if choice.pausedUntil != nil {
            state = .viewerPaused
        } else if visibilityState == .disabled || visibilityState == .viewerPaused {
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
            viewerSharingEnabled: choice.isEnabled,
            partnerSharingEnabled: partnerSharingEnabled,
            partnerLocation: partnerLocation,
            partnerLocationIsStale: partnerLocationIsStale,
            updatedAt: updatedAt,
            refreshedAt: refreshedAt,
            viewerPausedUntil: choice.pausedUntil
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

actor SwiftDataLocationVisibilityRepository: LocationVisibilitySnapshotPersisting {
    private let container: ModelContainer
    private let ledger: PendingSharingChoiceLedger

    init(container: ModelContainer, ledger: PendingSharingChoiceLedger = .shared) {
        self.container = container
        self.ledger = ledger
    }

    func save(_ snapshot: LocationVisibilitySnapshot) throws {
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
    ) throws {
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

    func load(ownerUserID: UUID, coupleID: UUID) throws -> LocationVisibilitySnapshot? {
        let context = ModelContext(container)
        return try fetch(ownerUserID: ownerUserID, coupleID: coupleID, in: context)?.snapshot
    }

    func setViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        choice: ViewerSharingChoice,
        updatedAt: Date,
        isPendingConfirmation: Bool
    ) throws {
        let key = LocalLocationVisibilitySnapshot.storageKey(ownerUserID: ownerUserID, coupleID: coupleID)
        try ledger.withChoices { choices in
            try applyViewerSharing(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                choice: choice,
                updatedAt: updatedAt
            )
            choices[key] = isPendingConfirmation ? choice : nil
        }
        LocalStoreChanges.post(.locationVisibility, ownerUserID: ownerUserID)
    }

    func confirmViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        confirmation: ViewerSharingConfirmation,
        updatedAt: Date,
        otherChoicesPending: Bool
    ) throws {
        let key = LocalLocationVisibilitySnapshot.storageKey(ownerUserID: ownerUserID, coupleID: coupleID)
        let applied = try ledger.withChoices { choices -> Bool in
            // The ledger holds the newest choice. It matches the operation that was sent, not the
            // answer: the server drops a pause whose end has passed while the phone was offline.
            if otherChoicesPending || choices[key].map({ $0 != confirmation.submitted }) == true {
                return false
            }
            try applyViewerSharing(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                choice: confirmation.confirmed,
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
        choice: ViewerSharingChoice,
        updatedAt: Date
    ) throws {
        let context = ModelContext(container)
        if let existing = try fetch(ownerUserID: ownerUserID, coupleID: coupleID, in: context) {
            existing.viewerSharingEnabled = choice.isEnabled
            existing.viewerPausedUntil = choice.pausedUntil
            let oldState = PartnerLocationVisibilityState(rawValue: existing.visibilityStateRawValue)
            if !choice.isEnabled {
                existing.visibilityStateRawValue = PartnerLocationVisibilityState.disabled.rawValue
            } else if choice.pausedUntil != nil {
                existing.visibilityStateRawValue = PartnerLocationVisibilityState.viewerPaused.rawValue
            } else if oldState == .disabled || oldState == .viewerPaused {
                existing.visibilityStateRawValue = PartnerLocationVisibilityState.unknown("local").rawValue
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
                        visibilityState: Self.state(for: choice),
                        viewerSharingEnabled: choice.isEnabled,
                        partnerSharingEnabled: false,
                        partnerLocation: nil,
                        partnerLocationIsStale: false,
                        updatedAt: updatedAt,
                        refreshedAt: updatedAt,
                        viewerPausedUntil: choice.pausedUntil
                    )
                )
            )
        }
        try context.save()
    }

    /// The state of a snapshot that only has the viewer's own choice to go on.
    fileprivate static func state(for choice: ViewerSharingChoice) -> PartnerLocationVisibilityState {
        if !choice.isEnabled {
            .disabled
        } else if choice.pausedUntil != nil {
            .viewerPaused
        } else {
            .unknown("local")
        }
    }

    func delete(ownerUserID: UUID, coupleID: UUID) throws {
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

    func save(_ snapshot: OwnLocationSnapshot) throws {
        let context = ModelContext(container)
        if let existing = try fetch(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID, in: context) {
            existing.update(from: snapshot)
        } else {
            context.insert(LocalOwnLocationSnapshot(snapshot: snapshot))
        }
        try context.save()
        LocalStoreChanges.post(.ownLocation, ownerUserID: snapshot.ownerUserID)
    }

    func load(ownerUserID: UUID, coupleID: UUID) throws -> OwnLocationSnapshot? {
        let context = ModelContext(container)
        return try fetch(ownerUserID: ownerUserID, coupleID: coupleID, in: context)?.snapshot
    }

    func clearPendingOperation(
        ownerUserID: UUID,
        coupleID: UUID,
        operationID: UUID
    ) throws {
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

    func delete(ownerUserID: UUID, coupleID: UUID) throws {
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
