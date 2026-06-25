import Foundation
import Testing
@testable import PaeoniaApp

struct LocalPendingSyncOperationTests {
    @Test func pendingOperationPreservesEnvelopeAndLifecycle() throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let operationID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let clientID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let localCreatedAt = Date(timeIntervalSince1970: 100)
        let operation = SyncClientOperation(
            id: operationID,
            clientID: clientID,
            clientSequence: 9,
            localCreatedAt: localCreatedAt
        )
        let pendingOperation = LocalPendingSyncOperation(
            ownerUserID: ownerUserID,
            operation: operation,
            operationKind: .submitDailyAnswer,
            idempotencyScope: "daily-answer:\(operationID.uuidString)"
        )

        pendingOperation.markSending(at: Date(timeIntervalSince1970: 200))
        pendingOperation.markRetryableFailure(
            "Offline",
            nextRetryAt: Date(timeIntervalSince1970: 260),
            at: Date(timeIntervalSince1970: 210)
        )
        pendingOperation.markSucceeded(at: Date(timeIntervalSince1970: 300))

        #expect(pendingOperation.operationEnvelope == operation)
        #expect(pendingOperation.operationKind == .submitDailyAnswer)
        #expect(pendingOperation.attemptCount == 1)
        #expect(pendingOperation.status == .succeeded)
        #expect(pendingOperation.completedAt == Date(timeIntervalSince1970: 300))
        #expect(pendingOperation.lastError == nil)
        #expect(pendingOperation.nextRetryAt == nil)
    }
}
