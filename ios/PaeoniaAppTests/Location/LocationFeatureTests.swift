import Foundation
import Testing
@testable import PaeoniaApp

struct LocationSnapshotRepositoryTests {
    @Test
    func visibilityRepositoryPersistsPartnerLocationAndStaleState() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataLocationVisibilityRepository(container: store.container)
        let snapshot = try visibilitySnapshot(
            visibilityState: .visible,
            partnerLocationIsStale: true
        )

        try await repository.save(snapshot)

        let loaded = try await repository.load(
            ownerUserID: snapshot.ownerUserID,
            coupleID: snapshot.coupleID
        )
        #expect(loaded == snapshot)
        #expect(loaded?.partnerLocationIsStale == true)
    }

    @Test
    func ownLocationRepositoryReplacesStoredLocation() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataOwnLocationSnapshotRepository(container: store.container)
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let first = OwnLocationSnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: LocationPoint(
                latitude: 59.91,
                longitude: 10.75,
                capturedAt: Date(timeIntervalSince1970: 100)
            ),
            source: .foregroundOpen,
            pendingOperationID: nil,
            updatedAt: Date(timeIntervalSince1970: 101)
        )
        let replacementOperationID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let replacement = OwnLocationSnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: LocationPoint(
                latitude: 69.96,
                longitude: 23.27,
                accuracyMeters: 12,
                capturedAt: Date(timeIntervalSince1970: 200)
            ),
            source: .manualRefresh,
            pendingOperationID: replacementOperationID,
            updatedAt: Date(timeIntervalSince1970: 201)
        )

        try await repository.save(first)
        try await repository.save(replacement)

        let loaded = try await repository.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(loaded == replacement)
    }
}

struct LocationSharingPrimerStoreTests {
    @Test
    func responsePersistsPerUserAndRelationshipWithoutPlaintextIdentifiers() throws {
        let suiteName = "LocationSharingPrimerStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let ownerUserID = locationTestUUID("11111111-1111-1111-1111-111111111111")
        let otherUserID = locationTestUUID("44444444-4444-4444-4444-444444444444")
        let coupleID = locationTestUUID("22222222-2222-2222-2222-222222222222")
        let otherCoupleID = locationTestUUID("55555555-5555-5555-5555-555555555555")
        let store = UserDefaultsLocationSharingPrimerStore(defaults: defaults)

        #expect(!store.hasResponded(ownerUserID: ownerUserID, coupleID: coupleID))
        store.markResponded(ownerUserID: ownerUserID, coupleID: coupleID)

        let restoredStore = UserDefaultsLocationSharingPrimerStore(defaults: defaults)
        #expect(restoredStore.hasResponded(ownerUserID: ownerUserID, coupleID: coupleID))
        #expect(!restoredStore.hasResponded(ownerUserID: otherUserID, coupleID: coupleID))
        #expect(!restoredStore.hasResponded(ownerUserID: ownerUserID, coupleID: otherCoupleID))

        let storedKeys = defaults.dictionaryRepresentation().keys.joined(separator: " ")
        #expect(!storedKeys.contains(ownerUserID.uuidString.lowercased()))
        #expect(!storedKeys.contains(coupleID.uuidString.lowercased()))
    }

    @MainActor
    @Test
    func locationPrimerShowsWithoutWaitingForNotifications() throws {
        let suiteName = "LocationSharingPrimerCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let identity = LocationIdentity(
            currentUserID: locationTestUUID("11111111-1111-1111-1111-111111111111"),
            coupleID: locationTestUUID("22222222-2222-2222-2222-222222222222")
        )
        let pushStore = UserDefaultsPushPermissionPrimerStore(defaults: defaults)
        let coordinator = RootPairingPermissionPrimerCoordinator(
            pushPrimerStore: pushStore,
            locationPrimerStore: UserDefaultsLocationSharingPrimerStore(defaults: defaults)
        )

        coordinator.presentLocationPrimerIfNeeded(
            identity: identity,
            sharingStateIsKnown: true,
            sharingEnabled: true,
            locationAuthorizationState: .notDetermined
        )

        #expect(coordinator.presentedPrimer == .location)
        #expect(!pushStore.hasResponded())
    }

    @MainActor
    @Test
    func dismissingNotificationPrimerDoesNotRepeatItInTheSameSession() async throws {
        let suiteName = "LocationSharingPrimerDismissTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let identity = LocationIdentity(
            currentUserID: locationTestUUID("11111111-1111-1111-1111-111111111111"),
            coupleID: locationTestUUID("22222222-2222-2222-2222-222222222222")
        )
        let pushStore = UserDefaultsPushPermissionPrimerStore(defaults: defaults)
        let coordinator = RootPairingPermissionPrimerCoordinator(
            pushPrimerStore: pushStore,
            locationPrimerStore: UserDefaultsLocationSharingPrimerStore(defaults: defaults)
        )

        await coordinator.presentNotificationPrimerIfNeeded(
            identity: identity,
            pushAuthorization: StaticPushAuthorization(isNotDetermined: true)
        )
        #expect(coordinator.presentedPrimer == .notifications)

        coordinator.dismiss()
        await coordinator.presentNotificationPrimerIfNeeded(
            identity: identity,
            pushAuthorization: StaticPushAuthorization(isNotDetermined: true)
        )

        #expect(coordinator.presentedPrimer == nil)
        #expect(!pushStore.hasResponded())
    }

    @MainActor
    @Test
    func locationPrimerAppearsOnlyOncePerRelationshipInOneSession() throws {
        let suiteName = "LocationSharingPrimerOnceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let identity = LocationIdentity(
            currentUserID: locationTestUUID("11111111-1111-1111-1111-111111111111"),
            coupleID: locationTestUUID("22222222-2222-2222-2222-222222222222")
        )
        let coordinator = RootPairingPermissionPrimerCoordinator(
            pushPrimerStore: UserDefaultsPushPermissionPrimerStore(defaults: defaults),
            locationPrimerStore: UserDefaultsLocationSharingPrimerStore(defaults: defaults)
        )

        coordinator.presentLocationPrimerIfNeeded(
            identity: identity,
            sharingStateIsKnown: true,
            sharingEnabled: false,
            locationAuthorizationState: .notDetermined
        )
        #expect(coordinator.presentedPrimer == .location)

        coordinator.dismiss()
        coordinator.presentLocationPrimerIfNeeded(
            identity: identity,
            sharingStateIsKnown: true,
            sharingEnabled: false,
            locationAuthorizationState: .notDetermined
        )

        #expect(coordinator.presentedPrimer == nil)
    }

    @MainActor
    @Test
    func newerIdentityWinsWhileOlderPushEvaluationIsSuspended() async throws {
        let suiteName = "LocationSharingPrimerCoordinatorRaceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstIdentity = LocationIdentity(
            currentUserID: locationTestUUID("11111111-1111-1111-1111-111111111111"),
            coupleID: locationTestUUID("22222222-2222-2222-2222-222222222222")
        )
        let latestIdentity = LocationIdentity(
            currentUserID: firstIdentity.currentUserID,
            coupleID: locationTestUUID("55555555-5555-5555-5555-555555555555")
        )
        let pushAuthorization = SequencedPushAuthorization()
        let coordinator = RootPairingPermissionPrimerCoordinator(
            pushPrimerStore: UserDefaultsPushPermissionPrimerStore(defaults: defaults),
            locationPrimerStore: UserDefaultsLocationSharingPrimerStore(defaults: defaults)
        )

        let staleEvaluation = Task { @MainActor in
            await coordinator.presentNotificationPrimerIfNeeded(
                identity: firstIdentity,
                pushAuthorization: pushAuthorization
            )
        }
        await pushAuthorization.waitUntilFirstEvaluationStarts()
        await coordinator.presentNotificationPrimerIfNeeded(
            identity: latestIdentity,
            pushAuthorization: pushAuthorization
        )
        await pushAuthorization.finishFirstEvaluation()
        await staleEvaluation.value

        #expect(coordinator.presentedPrimer == .notifications)
        #expect(coordinator.presentedIdentity == latestIdentity)
    }

    @MainActor
    @Test
    func deniedLocationAuthorizationNeverShowsDeadEndLocationPrimer() throws {
        let suiteName = "LocationSharingPrimerDeniedTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let identity = LocationIdentity(
            currentUserID: locationTestUUID("11111111-1111-1111-1111-111111111111"),
            coupleID: locationTestUUID("22222222-2222-2222-2222-222222222222")
        )
        let coordinator = RootPairingPermissionPrimerCoordinator(
            pushPrimerStore: UserDefaultsPushPermissionPrimerStore(defaults: defaults),
            locationPrimerStore: UserDefaultsLocationSharingPrimerStore(defaults: defaults)
        )

        coordinator.presentLocationPrimerIfNeeded(
            identity: identity,
            sharingStateIsKnown: true,
            sharingEnabled: false,
            locationAuthorizationState: .denied
        )

        #expect(coordinator.presentedPrimer == nil)
    }
}

struct LocationGatewayRequestEncodingTests {
    @Test
    func preferenceRequestEncodesNilConsentVersionAsNull() throws {
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let request = UpdateLocationSharingPreferenceRequest(
            payload: LocationSharingOperationPayload(
                coupleID: coupleID,
                isEnabled: false,
                consentVersion: nil,
                source: .settingsToggle
            ),
            operation: try operation(id: "33333333-3333-3333-3333-333333333333")
        )

        let encoded = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded)
        let object = try #require(json as? [String: Any])

        #expect(object.keys.contains("p_consent_version"))
        #expect(object["p_consent_version"] is NSNull)
        #expect(object["p_is_enabled"] as? Bool == false)
    }

    @Test
    func latestLocationRequestEncodesNilAccuracyAsNull() throws {
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let request = UpdateLatestPartnerLocationRequest(
            payload: LatestPartnerLocationOperationPayload(
                coupleID: coupleID,
                location: LocationPoint(
                    latitude: 59,
                    longitude: 10,
                    capturedAt: Date(timeIntervalSince1970: 100)
                ),
                source: .manualRefresh
            ),
            operation: try operation(id: "33333333-3333-3333-3333-333333333333")
        )

        let encoded = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded)
        let object = try #require(json as? [String: Any])

        #expect(object.keys.contains("p_accuracy_m"))
        #expect(object["p_accuracy_m"] is NSNull)
        #expect(object["p_source"] as? String == LocationSharingSource.manualRefresh.rawValue)
    }
}

struct LocationDisplayRecencyTests {
    private let capturedAt = Date(timeIntervalSince1970: 1_000)

    @Test func locationRemainsRecentBeforeTwentyFourHours() {
        let now = capturedAt.addingTimeInterval(LocationDisplayRecency.staleAfter - 1)

        #expect(LocationDisplayRecency.resolve(capturedAt: capturedAt, now: now) == .recent)
    }

    @Test func locationBecomesStaleAtTwentyFourHours() {
        let now = capturedAt.addingTimeInterval(LocationDisplayRecency.staleAfter)

        #expect(LocationDisplayRecency.resolve(capturedAt: capturedAt, now: now) == .stale)
    }

    @Test func futureCaptureTimeDoesNotAppearStale() {
        #expect(LocationDisplayRecency.resolve(
            capturedAt: capturedAt.addingTimeInterval(60),
            now: capturedAt
        ) == .recent)
    }

    @Test func serverStaleStateWinsWhenDeviceClockIsBehind() {
        #expect(LocationDisplayRecency.resolve(
            capturedAt: capturedAt,
            now: capturedAt,
            wasStaleAtLastRefresh: true
        ) == .stale)
    }
}

struct RoutineLocationThrottleTests {
    private let oslo = LocationPoint(
        latitude: 59.9139,
        longitude: 10.7522,
        capturedAt: Date(timeIntervalSince1970: 1_000)
    )

    @Test func sendsWhenNoPreviousFix() {
        #expect(RoutineLocationThrottle.shouldSend(
            lastSent: nil,
            current: oslo,
            now: Date(timeIntervalSince1970: 1_000)
        ))
    }

    @Test func skipsWhenRecentAndBarelyMoved() {
        let now = oslo.capturedAt.addingTimeInterval(60)
        // ~70 m away.
        let nearby = LocationPoint(latitude: 59.9145, longitude: 10.7525, capturedAt: now)
        #expect(!RoutineLocationThrottle.shouldSend(lastSent: oslo, current: nearby, now: now))
    }

    @Test func sendsWhenMovedFarEvenIfRecent() {
        let now = oslo.capturedAt.addingTimeInterval(60)
        // ~2 km away.
        let farAway = LocationPoint(latitude: 59.9319, longitude: 10.7522, capturedAt: now)
        #expect(RoutineLocationThrottle.shouldSend(lastSent: oslo, current: farAway, now: now))
    }

    @Test func sendsWhenFixIsStaleEvenIfStationary() {
        let now = oslo.capturedAt.addingTimeInterval(RoutineLocationThrottle.minimumInterval)
        let sameSpot = LocationPoint(latitude: oslo.latitude, longitude: oslo.longitude, capturedAt: now)
        #expect(RoutineLocationThrottle.shouldSend(lastSent: oslo, current: sameSpot, now: now))
    }
}

@MainActor
struct PartnerLocationShortAgeTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func age(_ seconds: TimeInterval) -> String {
        PartnerLocationRecordedStatus.shortAge(capturedAt: now.addingTimeInterval(-seconds), now: now)
    }

    @Test
    func showsOneLargestUnitWithoutWords() {
        #expect(age(3 * 60) == Duration.seconds(180).formatted(
            .units(allowed: [.minutes], width: .abbreviated)
        ))
        #expect(!age(3 * 60).contains("ago"))
        #expect(age(2 * 60 * 60) == Duration.seconds(7_200).formatted(
            .units(allowed: [.hours], width: .abbreviated)
        ))
    }

    @Test
    func freshOrFutureCapturesReadJustNow() {
        let justNow = String(localized: .homeMapAgeJustNow)
        #expect(age(5) == justNow)
        #expect(age(-30) == justNow)
        #expect(age(60) != justNow)
    }
}
