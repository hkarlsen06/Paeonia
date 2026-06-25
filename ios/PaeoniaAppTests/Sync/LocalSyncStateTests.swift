import Foundation
import Testing
@testable import PaeoniaApp

struct LocalSyncStateTests {
    @Test func keyIsStableForOwnerScopeAndStream() throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))

        let state = LocalSyncState(
            ownerUserID: ownerUserID,
            scopeKind: .couple,
            scopeID: coupleID,
            streamKey: .relationship
        )

        #expect(state.key == [
            ownerUserID.uuidString.lowercased(),
            SyncScopeKind.couple.rawValue,
            coupleID.uuidString.lowercased(),
            SyncStreamKey.relationship.rawValue
        ].joined(separator: "|"))
    }

    @Test func successfulSyncStoresCursorAndClearsError() throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let tieID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let state = LocalSyncState(
            ownerUserID: ownerUserID,
            scopeKind: .user,
            streamKey: .profile
        )
        let attemptDate = Date(timeIntervalSince1970: 100)
        let successDate = Date(timeIntervalSince1970: 200)
        let cursorDate = Date(timeIntervalSince1970: 150)

        state.markFailed("Network unavailable", at: attemptDate)
        state.markSucceeded(
            cursor: SyncCursor(updatedAt: cursorDate, tieID: tieID),
            at: successDate
        )

        #expect(state.lastSyncError == nil)
        #expect(state.lastUpdatedAt == cursorDate)
        #expect(state.lastTieID == tieID)
        #expect(state.lastSuccessfulSyncAt == successDate)
        #expect(state.lastSyncAttemptAt == successDate)
    }
}
