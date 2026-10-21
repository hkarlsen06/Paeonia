import CoreLocation
import Foundation
import Testing
@testable import PaeoniaApp

struct LocationUpdatePlanTests {
    private func plan(
        isAppActive: Bool = true,
        sharingEnabled: Bool? = true,
        hasIdentity: Bool = true,
        authorization: CLAuthorizationStatus = .authorizedAlways,
        prefersUpdatesWhileClosed: Bool = true
    ) -> LocationUpdatePlan {
        LocationUpdatePlan.resolve(
            isAppActive: isAppActive,
            sharingEnabled: sharingEnabled,
            hasIdentity: hasIdentity,
            authorization: authorization,
            prefersUpdatesWhileClosed: prefersUpdatesWhileClosed
        )
    }

    @Test func openAppWatchesOnlyWhileSharingWithAccess() {
        #expect(plan(authorization: .authorizedWhenInUse).watchesWhileOpen)
        #expect(!plan(isAppActive: false).watchesWhileOpen)
        #expect(!plan(sharingEnabled: false).watchesWhileOpen)
        #expect(!plan(sharingEnabled: nil).watchesWhileOpen)
        #expect(!plan(authorization: .denied).watchesWhileOpen)
        #expect(!plan(hasIdentity: false).watchesWhileOpen)
    }

    @Test func closedAppNeedsTheChoiceAndAlwaysAccess() {
        #expect(plan(isAppActive: false).watchesWhileClosed)
        #expect(!plan(prefersUpdatesWhileClosed: false).watchesWhileClosed)
        #expect(!plan(authorization: .authorizedWhenInUse).watchesWhileClosed)
        #expect(!plan(sharingEnabled: false).watchesWhileClosed)
        #expect(!plan(hasIdentity: false).watchesWhileClosed)
    }

    /// A launch in the background has not loaded the sharing choice yet. The
    /// closed-app feed keeps running and the uploader checks sharing itself.
    @Test func closedAppKeepsWatchingBeforeSharingLoads() {
        #expect(plan(isAppActive: false, sharingEnabled: nil).watchesWhileClosed)
    }

    @Test func sessionGoalFollowsTheFeedThatNeedsIt() {
        #expect(plan().sessionGoal == .always)
        #expect(plan(prefersUpdatesWhileClosed: false).sessionGoal == .whenInUse)
        // A relaunch in the background retakes the Always session at once.
        #expect(plan(isAppActive: false, sharingEnabled: nil).sessionGoal == .always)
        // The Always goal is held before the person grants Always access.
        #expect(plan(authorization: .authorizedWhenInUse).sessionGoal == .always)
    }

    @Test func noSessionWhenNothingNeedsLocation() {
        #expect(plan(isAppActive: false, prefersUpdatesWhileClosed: false).sessionGoal == nil)
        #expect(plan(sharingEnabled: false, prefersUpdatesWhileClosed: false).sessionGoal == nil)
        #expect(plan(sharingEnabled: false).sessionGoal == nil)
        #expect(plan(hasIdentity: false).sessionGoal == nil)
    }
}

@MainActor
struct BackgroundLocationUploaderTests {
    private let ownerUserID = UUID()
    private let coupleID = UUID()
    private let now = Date(timeIntervalSince1970: 10_000)

    private func location(latitude: Double = 59.9, capturedAt: Date? = nil) -> LocationPoint {
        LocationPoint(latitude: latitude, longitude: 10.7, capturedAt: capturedAt ?? now)
    }

    private func makeUploader(
        gateway: BackgroundTestLocationGateway,
        sharing: Bool,
        lastSent: LocationPoint? = nil,
        visibilityStore: InMemoryLocationVisibilityRepository = InMemoryLocationVisibilityRepository(),
        now uploaderNow: Date? = nil
    ) async throws -> (BackgroundLocationUploader, InMemoryOwnLocationSnapshotRepository) {
        let clock = uploaderNow ?? now
        if uploaderNow == nil {
            try await visibilityStore.setViewerSharingEnabled(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                isEnabled: sharing,
                updatedAt: now
            )
        }
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        if let lastSent {
            try await ownLocationStore.save(OwnLocationSnapshot(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                location: lastSent,
                source: .foregroundOpen,
                pendingOperationID: nil,
                updatedAt: lastSent.capturedAt
            ))
        }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let uploader = BackgroundLocationUploader(
            gateway: gateway,
            visibilityStore: visibilityStore,
            ownLocationStore: ownLocationStore,
            operationProvider: SyncClientOperationFactory(defaults: defaults),
            now: { clock }
        )
        return (uploader, ownLocationStore)
    }

    @Test func sendsAndStoresTheLocationAsBackground() async throws {
        let gateway = BackgroundTestLocationGateway()
        let (uploader, ownLocationStore) = try await makeUploader(gateway: gateway, sharing: true)

        let outcome = await uploader.upload(location(), ownerUserID: ownerUserID, coupleID: coupleID)

        #expect(outcome == .sent)
        #expect(await gateway.payloads.map(\.source) == [.background])
        let stored = try await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(stored?.location.latitude == 59.9)
        #expect(stored?.source == .background)
        #expect(stored?.pendingOperationID == nil)
    }

    @Test func sendsNothingWhenSharingIsOff() async throws {
        let gateway = BackgroundTestLocationGateway()
        let (uploader, _) = try await makeUploader(gateway: gateway, sharing: false)

        let outcome = await uploader.upload(location(), ownerUserID: ownerUserID, coupleID: coupleID)

        #expect(outcome == .sharingOff)
        #expect(await gateway.payloads.isEmpty)
    }

    @Test func sendsNothingWhileSharingIsPausedAndResumesAfterThePause() async throws {
        let gateway = BackgroundTestLocationGateway()
        let visibilityStore = InMemoryLocationVisibilityRepository()
        let (uploader, _) = try await makeUploader(gateway: gateway, sharing: true, visibilityStore: visibilityStore)
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            pausedUntil: now.addingTimeInterval(60),
            updatedAt: now
        )

        #expect(await uploader.upload(location(), ownerUserID: ownerUserID, coupleID: coupleID) == .paused)
        #expect(await gateway.payloads.isEmpty)

        // The pause's time has passed on this phone's clock, even if the server has not cleared it yet.
        let (laterUploader, _) = try await makeUploader(
            gateway: gateway,
            sharing: true,
            visibilityStore: visibilityStore,
            now: now.addingTimeInterval(61)
        )
        let later = location(capturedAt: now.addingTimeInterval(61))
        #expect(await laterUploader.upload(later, ownerUserID: ownerUserID, coupleID: coupleID) == .sent)
    }

    @Test func serverRefusalForAPauseKeepsUpdatesOn() async throws {
        let gateway = BackgroundTestLocationGateway(error: PaeoniaConvexError.server(
            code: "42501",
            message: "location sharing is paused"
        ))
        let (uploader, _) = try await makeUploader(gateway: gateway, sharing: true)

        #expect(await uploader.upload(location(), ownerUserID: ownerUserID, coupleID: coupleID) == .paused)
    }

    @Test func skipsARecentLocationNearby() async throws {
        let gateway = BackgroundTestLocationGateway()
        let lastSent = location(latitude: 59.9005, capturedAt: now.addingTimeInterval(-60))
        let (uploader, _) = try await makeUploader(gateway: gateway, sharing: true, lastSent: lastSent)

        let outcome = await uploader.upload(location(), ownerUserID: ownerUserID, coupleID: coupleID)

        #expect(outcome == .skipped)
        #expect(await gateway.payloads.isEmpty)
    }

    @Test func serverRefusalForSharingOffStopsUpdates() async throws {
        let gateway = BackgroundTestLocationGateway(error: PaeoniaConvexError.server(
            code: "42501",
            message: "location sharing must be enabled before updating location"
        ))
        let (uploader, ownLocationStore) = try await makeUploader(gateway: gateway, sharing: true)

        let outcome = await uploader.upload(location(), ownerUserID: ownerUserID, coupleID: coupleID)

        #expect(outcome == .sharingOff)
        #expect(try await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID) == nil)
    }

    /// Turning sharing off while the request is in flight marks it off and
    /// deletes the stored location. The finished upload must not put it back.
    @Test func optOutDuringSendLeavesNoStoredLocation() async throws {
        let visibilityStore = InMemoryLocationVisibilityRepository()
        let gateway = BackgroundTestLocationGateway { [ownerUserID, coupleID, now] in
            try? await visibilityStore.setViewerSharingEnabled(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                isEnabled: false,
                updatedAt: now
            )
        }
        let (uploader, ownLocationStore) = try await makeUploader(
            gateway: gateway,
            sharing: true,
            visibilityStore: visibilityStore
        )

        _ = await uploader.upload(location(), ownerUserID: ownerUserID, coupleID: coupleID)

        #expect(try await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID) == nil)
    }

    @Test func cancelledUploadSavesNothing() async throws {
        let gateway = BackgroundTestLocationGateway {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let (uploader, ownLocationStore) = try await makeUploader(gateway: gateway, sharing: true)

        let outcome = await uploader.upload(location(), ownerUserID: ownerUserID, coupleID: coupleID)

        #expect(outcome == .cancelled)
        #expect(try await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID) == nil)
    }

    /// A store that cannot be read says nothing about the choice, so the
    /// switch must stay on.
    @Test func unreadableStoreIsAFailureNotSharingOff() async {
        let uploader = BackgroundLocationUploader(
            gateway: BackgroundTestLocationGateway(),
            visibilityStore: UnreadableVisibilityStore(),
            ownLocationStore: InMemoryOwnLocationSnapshotRepository()
        )

        let outcome = await uploader.upload(location(), ownerUserID: ownerUserID, coupleID: coupleID)

        #expect(outcome == .failed)
    }

    @Test func otherFailuresKeepUpdatesRunning() async throws {
        let gateway = BackgroundTestLocationGateway(error: URLError(.notConnectedToInternet))
        let (uploader, ownLocationStore) = try await makeUploader(gateway: gateway, sharing: true)

        let outcome = await uploader.upload(location(), ownerUserID: ownerUserID, coupleID: coupleID)

        #expect(outcome == .failed)
        #expect(try await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID) == nil)
    }
}

private actor BackgroundTestLocationGateway: LocationGateway {
    private let error: (any Error)?
    /// Runs while the request is "in flight".
    private let duringSend: @Sendable () async -> Void
    private(set) var payloads: [LatestPartnerLocationOperationPayload] = []

    init(error: (any Error)? = nil, duringSend: @escaping @Sendable () async -> Void = {}) {
        self.error = error
        self.duringSend = duringSend
    }

    func updateLocationSharingPreference(
        payload _: LocationSharingOperationPayload,
        operation _: SyncClientOperation
    ) throws -> LocationSharingPreferenceUpdateResponse? {
        nil
    }

    func updateLatestPartnerLocation(
        payload: LatestPartnerLocationOperationPayload,
        operation _: SyncClientOperation
    ) async throws -> LatestPartnerLocationUpdateResponse? {
        payloads.append(payload)
        await duringSend()
        if let error {
            throw error
        }
        return nil
    }
}

private actor UnreadableVisibilityStore: LocationVisibilitySnapshotPersisting {
    func save(_: LocationVisibilitySnapshot) throws {}

    func load(ownerUserID _: UUID, coupleID _: UUID) throws -> LocationVisibilitySnapshot? {
        throw CocoaError(.fileReadUnknown)
    }

    func saveRemote(_: LocationVisibilitySnapshot, preservingLocalSharingChoiceIf _: Bool) throws {}

    func setViewerSharing(
        ownerUserID _: UUID,
        coupleID _: UUID,
        choice _: ViewerSharingChoice,
        updatedAt _: Date,
        isPendingConfirmation _: Bool
    ) throws {}

    func confirmViewerSharing(
        ownerUserID _: UUID,
        coupleID _: UUID,
        confirmation _: ViewerSharingConfirmation,
        updatedAt _: Date,
        otherChoicesPending _: Bool
    ) throws {}

    func delete(ownerUserID _: UUID, coupleID _: UUID) throws {}
}
