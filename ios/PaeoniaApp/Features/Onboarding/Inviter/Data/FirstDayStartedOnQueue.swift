import Foundation

nonisolated struct SetFirstDayStartedOnPayload: Codable, Equatable, Sendable {
    let startedOn: String
}

/// Saves the date the couple got together, picked during profile setup before there is
/// a couple. The date goes into the pending operations first, so it is never lost: the
/// sync sends it once profile setup is done, and retries until the server has it.
@MainActor
final class FirstDayStartedOnQueue {
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private let operationProvider: any SyncClientOperationProviding

    init(
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil
    ) {
        self.pendingOperationStore = pendingOperationStore ?? Self.defaultPendingOperationStore()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
    }

    func save(_ startedOn: PairingStartDate, ownerUserID: UUID) async throws {
        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operationProvider.makeOperation(),
                operationKind: .setFirstDayStartedOn,
                idempotencyScope: "first_day_draft:started_on",
                requestData: try JSONEncoder().encode(SetFirstDayStartedOnPayload(startedOn: startedOn.rawValue))
            )
        )
    }

    private static func defaultPendingOperationStore() -> any PendingSyncOperationPersisting {
        if let localStore = PaeoniaLocalStore.shared {
            return SwiftDataPendingSyncOperationRepository(container: localStore.container)
        }
        return InMemoryPendingSyncOperationRepository()
    }
}

/// Sends a queued start date to the first day draft. When the partner joined before it
/// went out, the date goes to the couple instead, unless the couple already has one.
struct FirstDayStartedOnPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .setFirstDayStartedOn

    let gateway: any FirstDayGateway
    /// Queues the couple's date write (`relationship:set_couple_started_on`).
    let relationshipDates: any RelationshipStartedOnDataServicing
    /// A new operation for that write. The refused one stays with this queued date.
    var operationFactory: any WidgetCanvasClientOperationProviding = WidgetCanvasClientOperationFactory.shared

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing first day start date payload")
        }
        let payload = try JSONDecoder().decodeQueuedPayload(SetFirstDayStartedOnPayload.self, from: requestData)
        do {
            try await gateway.setStartedOn(payload.startedOn, operation: operation.operation)
            return .succeeded
        } catch let error as PaeoniaConvexError where Self.isAlreadyPaired(error) {
            // A date the couple already has may be one the partner picked on purpose.
            if try await relationshipDates.loadStartedOn(ownerUserID: operation.ownerUserID).startedOn != nil {
                return .succeeded
            }
            try await relationshipDates.setStartedOn(
                try PairingStartDate(rawValue: payload.startedOn),
                ownerUserID: operation.ownerUserID,
                operation: await operationFactory.makeOperation()
            )
            return .succeeded
        } catch let error as PaeoniaConvexError where Self.isPermanent(error) {
            return .terminalFailure(error.description)
        }
    }

    nonisolated static func isAlreadyPaired(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, message) = error else { return false }
        return code == "23505" && message.contains("user already has an active couple")
    }

    /// A date in the future or a bad format, or another refusal of the request. A
    /// missing subscription is not a refusal here, since the date is saved before the
    /// paywall.
    nonisolated static func isPermanent(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, _) = error else { return false }
        return ["23514", "22007", "22P02", "23505"].contains(code)
    }
}
