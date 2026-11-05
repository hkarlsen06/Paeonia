import Foundation
import Testing
@testable import PaeoniaApp

/// Siri, Shortcuts and Spotlight act only for a signed-in, paired couple with access, as the
/// session, data owner and access snapshot saved on the phone say.
@MainActor
struct SiriAccessTests {
    private let session = AuthSession.test(profileStatus: .complete)

    private var ownerUserID: UUID {
        get throws { try #require(UUID(uuidString: session.id)) }
    }

    @Test func nobodySignedInIsSignedOut() async throws {
        let access = await siriAccess(session: nil, deviceOwner: nil, snapshot: nil)

        #expect(access == .signedOut)
    }

    @Test func anotherPersonsDataOnThePhoneCountsAsSignedOut() async throws {
        let access = await siriAccess(
            session: session,
            deviceOwner: UUID().uuidString,
            snapshot: .testPaired(ownerUserID: try ownerUserID)
        )

        #expect(access == .signedOut)
    }

    @Test func signedInWithoutARelationshipIsNotPaired() async throws {
        let owner = try ownerUserID
        let access = await siriAccess(
            session: session,
            deviceOwner: session.id,
            snapshot: AccessSyncSnapshot(
                ownerUserID: owner,
                userEntitlement: RemoteUserEntitlement(
                    userID: owner,
                    isEntitled: true,
                    source: "storekit",
                    status: "active",
                    productID: UUID(),
                    billingPeriod: nil,
                    currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
                ),
                coupleEntitlement: nil,
                relationshipState: nil
            )
        )

        #expect(access == .notPaired)
    }

    @Test func pairedWithoutASubscriptionHasNoAccess() async throws {
        let access = await siriAccess(
            session: session,
            deviceOwner: session.id,
            snapshot: .testPaywalled(ownerUserID: try ownerUserID)
        )

        #expect(access == .noAccess)
    }

    @Test func pairedWithAccessActsForTheCouple() async throws {
        let owner = try ownerUserID
        let coupleID = UUID()
        let access = await siriAccess(
            session: session,
            deviceOwner: session.id,
            snapshot: .testPaired(ownerUserID: owner, coupleID: coupleID, partnerDisplayName: "Riley")
        )

        let couple = try #require(access.couple)
        #expect(couple.ownerUserID == owner)
        #expect(couple.coupleID == coupleID)
        #expect(couple.partnerName == "Riley")
        #expect(access.refusal == nil)
    }

    @Test func entityQueriesRefuseAnAppThatLocksAfterAccessWasResolved() async throws {
        let access = await siriAccess(
            session: session, deviceOwner: session.id,
            snapshot: .testPaired(ownerUserID: try ownerUserID))
        #expect(access.coupleForEntityQuery(appIsLocked: false) == access.couple)
        #expect(access.coupleForEntityQuery(appIsLocked: true) == nil)
        #expect(SiriAccess.noAccess.coupleForEntityQuery(appIsLocked: false) == nil)
    }

    private func siriAccess(
        session: AuthSession?,
        deviceOwner: String?,
        snapshot: AccessSyncSnapshot?
    ) async -> SiriAccess {
        let snapshotStore = InMemoryAccessSyncSnapshotRepository()
        if let snapshot {
            try? await snapshotStore.save(snapshot)
        }
        let root = RootViewModel(
            syncService: TestPaeoniaSyncService(),
            authService: FlowAuthService(storedSession: session),
            accessSnapshotStore: snapshotStore,
            deviceOwnerStore: InMemoryRootDeviceOwnerStore(ownerUserID: deviceOwner)
        )
        return await root.siriAccess()
    }
}
