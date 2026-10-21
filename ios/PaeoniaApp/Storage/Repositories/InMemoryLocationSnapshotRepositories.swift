import Foundation

actor InMemoryLocationVisibilityRepository: LocationVisibilitySnapshotPersisting {
    private var snapshots: [String: LocationVisibilitySnapshot] = [:]
    private var pendingChoices: [String: ViewerSharingChoice] = [:]

    func save(_ snapshot: LocationVisibilitySnapshot) throws {
        snapshots[key(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID)] = snapshot
        LocalStoreChanges.post(.locationVisibility, ownerUserID: snapshot.ownerUserID)
    }

    func saveRemote(
        _ snapshot: LocationVisibilitySnapshot,
        preservingLocalSharingChoiceIf hasPendingSharingOperation: Bool
    ) throws {
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

    func load(ownerUserID: UUID, coupleID: UUID) throws -> LocationVisibilitySnapshot? {
        snapshots[key(ownerUserID: ownerUserID, coupleID: coupleID)]
    }

    func setViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        choice: ViewerSharingChoice,
        updatedAt: Date,
        isPendingConfirmation: Bool
    ) throws {
        applyViewerSharing(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            choice: choice,
            updatedAt: updatedAt
        )
        pendingChoices[key(ownerUserID: ownerUserID, coupleID: coupleID)] = isPendingConfirmation ? choice : nil
        LocalStoreChanges.post(.locationVisibility, ownerUserID: ownerUserID)
    }

    func confirmViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        confirmation: ViewerSharingConfirmation,
        updatedAt: Date,
        otherChoicesPending: Bool
    ) throws {
        let snapshotKey = key(ownerUserID: ownerUserID, coupleID: coupleID)
        if otherChoicesPending || pendingChoices[snapshotKey].map({ $0 != confirmation.submitted }) == true {
            return
        }
        applyViewerSharing(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            choice: confirmation.confirmed,
            updatedAt: updatedAt
        )
        pendingChoices[snapshotKey] = nil
        LocalStoreChanges.post(.locationVisibility, ownerUserID: ownerUserID)
    }

    private func applyViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        choice: ViewerSharingChoice,
        updatedAt: Date
    ) {
        let existing = snapshots[key(ownerUserID: ownerUserID, coupleID: coupleID)]
        let nextState: PartnerLocationVisibilityState
        if !choice.isEnabled {
            nextState = .disabled
        } else if choice.pausedUntil != nil {
            nextState = .viewerPaused
        } else if existing?.visibilityState == .disabled || existing?.visibilityState == .viewerPaused {
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
            viewerSharingEnabled: choice.isEnabled,
            partnerSharingEnabled: existing?.partnerSharingEnabled ?? false,
            partnerLocation: existing?.partnerLocation,
            partnerLocationIsStale: existing?.partnerLocationIsStale ?? false,
            updatedAt: updatedAt,
            refreshedAt: updatedAt,
            viewerPausedUntil: choice.pausedUntil
        )
    }

    func delete(ownerUserID: UUID, coupleID: UUID) throws {
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

    func save(_ snapshot: OwnLocationSnapshot) throws {
        snapshots[key(ownerUserID: snapshot.ownerUserID, coupleID: snapshot.coupleID)] = snapshot
        LocalStoreChanges.post(.ownLocation, ownerUserID: snapshot.ownerUserID)
    }

    func load(ownerUserID: UUID, coupleID: UUID) throws -> OwnLocationSnapshot? {
        snapshots[key(ownerUserID: ownerUserID, coupleID: coupleID)]
    }

    func clearPendingOperation(
        ownerUserID: UUID,
        coupleID: UUID,
        operationID: UUID
    ) throws {
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

    func delete(ownerUserID: UUID, coupleID: UUID) throws {
        snapshots[key(ownerUserID: ownerUserID, coupleID: coupleID)] = nil
        LocalStoreChanges.post(.ownLocation, ownerUserID: ownerUserID)
    }

    private func key(ownerUserID: UUID, coupleID: UUID) -> String {
        LocalOwnLocationSnapshot.storageKey(ownerUserID: ownerUserID, coupleID: coupleID)
    }
}
