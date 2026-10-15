import Foundation

/// Sends a queued countdown create or edit, then writes what the server stored into the
/// cache, so the timeline doesn't flash the old title between the send and the live feed.
struct SaveCountdownPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .saveCountdown

    let gateway: any CoupleDatesGateway
    let cache: any CoupleDatesCaching

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard case let .save(countdown) = CoupleDatesWrite(operation) else {
            return .terminalFailure("Missing countdown payload")
        }
        do {
            let stored = try await gateway.saveCountdown(countdown, operation: operation.operation)
            // Nil means the countdown was deleted, so the cache drops it too.
            let confirmed = stored.map(CoupleDatesWrite.save) ?? .delete(countdown.id)
            await cache.apply(confirmed, ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.coupleDates, ownerUserID: operation.ownerUserID)
            return .succeeded
        } catch let error as PaeoniaConvexError where CoupleDatesRejection.isPermanent(error) {
            return .terminalFailure(error.description)
        }
    }
}

struct DeleteCountdownPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .deleteCountdown

    let gateway: any CoupleDatesGateway
    let cache: any CoupleDatesCaching

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard case let .delete(id) = CoupleDatesWrite(operation) else {
            return .terminalFailure("Missing countdown delete payload")
        }
        do {
            try await gateway.deleteCountdown(id: id, operation: operation.operation)
            await cache.apply(.delete(id), ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.coupleDates, ownerUserID: operation.ownerUserID)
            return .succeeded
        } catch let error as PaeoniaConvexError where CoupleDatesRejection.isPermanent(error) {
            return .terminalFailure(error.description)
        }
    }
}

struct SetBirthdayPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .setBirthday

    let gateway: any CoupleDatesGateway
    let cache: any CoupleDatesCaching

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard case let .birthday(payload) = CoupleDatesWrite(operation) else {
            return .terminalFailure("Missing birthday payload")
        }
        do {
            let stored = try await gateway.setBirthday(payload, operation: operation.operation)
            await cache.apply(
                .birthday(SetBirthdayPayload(userID: stored.userID, birthday: stored.birthday)),
                ownerUserID: operation.ownerUserID
            )
            LocalStoreChanges.post(.coupleDates, ownerUserID: operation.ownerUserID)
            return .succeeded
        } catch let error as PaeoniaConvexError where CoupleDatesRejection.isPermanent(error) {
            return .terminalFailure(error.description)
        }
    }
}

nonisolated enum CoupleDatesRejection {
    /// Refusals a retry cannot fix: a bad title or date (`23514`, `22007`, `22P02`), or a
    /// countdown or person that belongs to another relationship. A missing subscription
    /// also comes back as `42501` and keeps retrying, so the write lands after a renewal.
    static func isPermanent(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, message) = error else { return false }
        switch code {
        case "23514", "22007", "22P02":
            return true
        case PaeoniaConvexError.accessDeniedCode:
            return ["another couple", "not in this relationship"].contains { message.contains($0) }
        default:
            return false
        }
    }
}
