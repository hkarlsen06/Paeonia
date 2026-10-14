import Foundation
import Testing
@testable import PaeoniaApp

/// The rules every game's queued writes share: which refusals are final, when an
/// upload is gone, and what happens after the server takes a move.
@MainActor
struct GameServerRejectionTests {
    private func makeOperation() throws -> PendingSyncOperationSnapshot {
        try snapshot(
            .setGameRoundStar,
            GameStarPayload(roundID: UUID(), starred: true, createdAt: GameFixture.now)
        )
    }

    @Test func anUploadTheServerDeletedIsGoneForEveryGame() {
        let messages = [
            "game drawing asset is not usable",
            "exquisite corpse drawing asset is not usable",
            "exquisite corpse strip asset is not usable",
            "memory media asset is not usable"
        ]

        for message in messages {
            #expect(GameServerRejection.isUploadGone(.server(code: "23514", message: message)))
        }
        #expect(
            GameServerRejection.isUploadGone(
                .server(code: "42501", message: "media upload reservation is not available")
            )
        )
        #expect(!GameServerRejection.isUploadGone(.server(code: "23514", message: "the round already ended")))
        #expect(
            !GameServerRejection.isUploadGone(
                .server(code: "22023", message: "exquisite corpse strip asset is not usable")
            )
        )
    }

    @Test func aPermanentRefusalDropsTheWriteWithoutCounting() async throws {
        let operation = try makeOperation()
        var counted = 0

        let drop = await GameServerRejection.shouldDrop(
            .server(code: "23514", message: "the round already ended"),
            of: operation
        ) { _, _ in
            counted += 1
            return counted
        }

        #expect(drop)
        #expect(counted == 0)
    }

    @Test func anUnexplainedRefusalDropsTheWriteOnTheLimitedTry() async throws {
        let operation = try makeOperation()
        let error = PaeoniaConvexError.server(code: "22023", message: "something new")
        var seenOperationIDs: [UUID] = []
        var refusals = 0
        var results: [Bool] = []

        for _ in 0..<GameServerRejection.unexplainedRefusalLimit {
            let drop = await GameServerRejection.shouldDrop(error, of: operation) { operationID, ownerUserID in
                #expect(ownerUserID == operation.ownerUserID)
                seenOperationIDs.append(operationID)
                refusals += 1
                return refusals
            }
            results.append(drop)
        }

        #expect(results == [false, false, true])
        #expect(Set(seenOperationIDs) == [operation.operation.id])
    }

    @Test func aWaitIsNeverCounted() async throws {
        let operation = try makeOperation()
        var counted = 0

        let drop = await GameServerRejection.shouldDrop(
            .server(code: "55P03", message: "busy"),
            of: operation
        ) { _, _ in
            counted += 1
            return counted
        }

        #expect(!drop)
        #expect(counted == 0)
    }

    @Test func aRateLimitIsNeverCounted() async throws {
        let operation = try makeOperation()
        var counted = 0

        for _ in 0..<(GameServerRejection.unexplainedRefusalLimit + 1) {
            let drop = await GameServerRejection.shouldDrop(
                .server(code: "53300", message: "too many requests: mediaUpload"),
                of: operation
            ) { _, _ in
                counted += 1
                return counted
            }
            #expect(!drop)
        }
        #expect(counted == 0)
    }

    @Test func aMoveStaysQueuedWhenTheStateCouldNotBeRead() async throws {
        let operation = try makeOperation()

        let read = await readStateAfterAcceptedMove(operation) {}
        let failed = await readStateAfterAcceptedMove(operation) { throw ReadFailure() }

        #expect(read == .succeeded)
        guard case let .retry(after: retryDate) = failed else {
            Issue.record("A failed read must keep the move in the queue")
            return
        }
        #expect(retryDate != nil)
    }
}

private struct ReadFailure: Error {}
