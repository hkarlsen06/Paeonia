import Foundation

/// Sends a batch of taps. Hearts are small, so a refusal that a retry cannot fix
/// (a count the server rejects, or a couple that no longer has two active
/// partners) drops the batch. Everything else, such as being offline or sending
/// too often, keeps the batch in the queue.
struct SendHeartsPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .sendHearts

    private let gateway: any HeartsGateway

    init(gateway: any HeartsGateway) {
        self.gateway = gateway
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(HeartsSendPayload.self, from: data)
        else {
            return .terminalFailure("Missing hearts payload")
        }
        do {
            try await gateway.sendHearts(count: payload.count, operation: operation.operation)
            return .succeeded
        } catch let error as PaeoniaConvexError {
            if HeartsRejection.isPermanent(error) {
                return .terminalFailure(error.description)
            }
            throw error
        }
    }
}

/// Tells the server which hearts this person was shown. The server keeps the
/// larger total, so a repeat does nothing. A refusal that a retry cannot fix drops
/// the mark. The hearts then show again at most once, the next time Home opens.
struct MarkHeartsSeenPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .markHeartsSeen

    private let gateway: any HeartsGateway

    init(gateway: any HeartsGateway) {
        self.gateway = gateway
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(HeartsSeenPayload.self, from: data)
        else {
            return .terminalFailure("Missing hearts seen payload")
        }
        do {
            try await gateway.markHeartsSeen(seenTotal: payload.seenTotal)
            return .succeeded
        } catch let error as PaeoniaConvexError {
            if HeartsRejection.isPermanent(error) {
                return .terminalFailure(error.description)
            }
            throw error
        }
    }
}

nonisolated enum HeartsRejection {
    /// `23514`: the server rejected the numbers. `42501` with a message about the
    /// partner or the couple: nobody is there to receive the hearts. Sign-in
    /// problems also come back as `42501` and keep retrying.
    static func isPermanent(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, message) = error else { return false }
        switch code {
        case "23514":
            return true
        case PaeoniaConvexError.accessDeniedCode:
            return ["active partner", "couple access"].contains { message.contains($0) }
        default:
            return false
        }
    }
}
