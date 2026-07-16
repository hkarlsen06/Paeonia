import Foundation
import Testing
@testable import PaeoniaApp

struct LocationSnapshotRepositoryTests {
    @Test
    func visibilityRepositoryPersistsPartnerLocationAndStaleState() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataLocationVisibilitySnapshotRepository(container: store.container)
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

        let ownerUserID = testUUID("11111111-1111-1111-1111-111111111111")
        let otherUserID = testUUID("44444444-4444-4444-4444-444444444444")
        let coupleID = testUUID("22222222-2222-2222-2222-222222222222")
        let otherCoupleID = testUUID("55555555-5555-5555-5555-555555555555")
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
    func restoredServerOptInStillShowsPrimerWhenIOSPermissionIsUndecided() async throws {
        let suiteName = "LocationSharingPrimerCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let identity = LocationIdentity(
            currentUserID: testUUID("11111111-1111-1111-1111-111111111111"),
            coupleID: testUUID("22222222-2222-2222-2222-222222222222")
        )
        let coordinator = RootPairingPermissionPrimerCoordinator(
            pushPrimerStore: UserDefaultsPushPermissionPrimerStore(defaults: defaults),
            locationPrimerStore: UserDefaultsLocationSharingPrimerStore(defaults: defaults)
        )

        await coordinator.presentIfNeeded(
            identity: identity,
            sharingStateIsKnown: true,
            sharingEnabled: true,
            locationAuthorizationState: .notDetermined,
            pushAuthorization: StaticPushAuthorization(isNotDetermined: true)
        )

        #expect(coordinator.presentedPrimer == .location)
    }

    @MainActor
    @Test
    func newerIdentityWinsWhileOlderPushEvaluationIsSuspended() async throws {
        let suiteName = "LocationSharingPrimerCoordinatorRaceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstIdentity = LocationIdentity(
            currentUserID: testUUID("11111111-1111-1111-1111-111111111111"),
            coupleID: testUUID("22222222-2222-2222-2222-222222222222")
        )
        let latestIdentity = LocationIdentity(
            currentUserID: firstIdentity.currentUserID,
            coupleID: testUUID("55555555-5555-5555-5555-555555555555")
        )
        let pushAuthorization = SequencedPushAuthorization()
        let coordinator = RootPairingPermissionPrimerCoordinator(
            pushPrimerStore: UserDefaultsPushPermissionPrimerStore(defaults: defaults),
            locationPrimerStore: UserDefaultsLocationSharingPrimerStore(defaults: defaults)
        )

        let staleEvaluation = Task { @MainActor in
            await coordinator.presentIfNeeded(
                identity: firstIdentity,
                sharingStateIsKnown: true,
                sharingEnabled: true,
                locationAuthorizationState: .authorized,
                pushAuthorization: pushAuthorization
            )
        }
        await pushAuthorization.waitUntilFirstEvaluationStarts()
        await coordinator.presentIfNeeded(
            identity: latestIdentity,
            sharingStateIsKnown: true,
            sharingEnabled: true,
            locationAuthorizationState: .authorized,
            pushAuthorization: pushAuthorization
        )
        pushAuthorization.finishFirstEvaluation()
        await staleEvaluation.value

        #expect(coordinator.presentedPrimer == .notifications)
        #expect(coordinator.presentedIdentity == latestIdentity)
    }

    @MainActor
    @Test
    func deniedLocationAuthorizationNeverShowsDeadEndLocationPrimer() async throws {
        let suiteName = "LocationSharingPrimerDeniedTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let identity = LocationIdentity(
            currentUserID: testUUID("11111111-1111-1111-1111-111111111111"),
            coupleID: testUUID("22222222-2222-2222-2222-222222222222")
        )
        let coordinator = RootPairingPermissionPrimerCoordinator(
            pushPrimerStore: UserDefaultsPushPermissionPrimerStore(defaults: defaults),
            locationPrimerStore: UserDefaultsLocationSharingPrimerStore(defaults: defaults)
        )

        await coordinator.presentIfNeeded(
            identity: identity,
            sharingStateIsKnown: true,
            sharingEnabled: false,
            locationAuthorizationState: .denied,
            pushAuthorization: StaticPushAuthorization(isNotDetermined: true)
        )

        #expect(coordinator.presentedPrimer == .notifications)
    }
}

struct LocationVisibilitySyncStreamTests {
    @Test
    func pullStoresVisibilitySnapshotAndAdvancesCursor() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let snapshot = try visibilitySnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            visibilityState: .visible,
            partnerLocationIsStale: false
        )
        let gateway = RecordingLocationGateway(visibilitySnapshot: snapshot)
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
        let stream = LocationVisibilitySyncStream(
            gateway: gateway,
            visibilityStore: visibilityStore
        )
        let context = SyncContext(
            session: SyncSession(userID: ownerUserID, activeCoupleID: coupleID),
            reason: .manualRefresh,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )

        let cursor = try await stream.pull(context: context)

        let stored = try await visibilityStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(stored == snapshot)
        #expect(cursor == SyncCursor(updatedAt: snapshot.updatedAt, tieID: snapshot.coupleID))
    }
}

struct LocationPendingOperationHandlerTests {
    @Test
    func preferenceHandlerSendsRpcPayloadAndUpdatesLocalPreference() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = try operation(id: "33333333-3333-3333-3333-333333333333")
        let payload = LocationSharingPreferenceOperationPayload(
            coupleID: coupleID,
            isEnabled: true,
            consentVersion: "location-sharing-v1",
            source: .settingsToggle
        )
        let gateway = RecordingLocationGateway(
            preferenceResponse: LocationSharingPreferenceUpdateResponse(
                coupleID: coupleID,
                userID: ownerUserID,
                isEnabled: true,
                enabledAt: Date(timeIntervalSince1970: 100),
                disabledAt: nil,
                updatedAt: Date(timeIntervalSince1970: 101)
            )
        )
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
        let handler = LocationSharingPreferencePendingOperationHandler(
            gateway: gateway,
            visibilityStore: visibilityStore
        )

        let result = try await handler.send(
            pendingOperation(
                ownerUserID: ownerUserID,
                operation: operation,
                kind: .updateLocationSharingPreference,
                payload: payload
            ),
            context: syncContext(ownerUserID: ownerUserID, coupleID: coupleID)
        )

        #expect(result == .succeeded)
        let preferencePayloads = await gateway.preferencePayloads
        #expect(preferencePayloads == [payload])
        let stored = try await visibilityStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(stored?.viewerSharingEnabled == true)
    }

    @Test
    func staleLocationRetryIsTerminalAndDoesNotOverwriteLocalLocation() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = try operation(id: "33333333-3333-3333-3333-333333333333")
        let newerLocal = OwnLocationSnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: LocationPoint(
                latitude: 60,
                longitude: 11,
                capturedAt: Date(timeIntervalSince1970: 300)
            ),
            source: .manualRefresh,
            pendingOperationID: nil,
            updatedAt: Date(timeIntervalSince1970: 301)
        )
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        try await ownLocationStore.save(newerLocal)
        let handler = LatestPartnerLocationPendingOperationHandler(
            gateway: RecordingLocationGateway(
                locationError: StaleLocationError(description: "stale location update was rejected")
            ),
            ownLocationStore: ownLocationStore
        )
        let stalePayload = LatestPartnerLocationOperationPayload(
            coupleID: coupleID,
            location: LocationPoint(
                latitude: 59,
                longitude: 10,
                capturedAt: Date(timeIntervalSince1970: 200)
            ),
            source: .foregroundOpen
        )

        let result = try await handler.send(
            pendingOperation(
                ownerUserID: ownerUserID,
                operation: operation,
                kind: .updateLatestPartnerLocation,
                payload: stalePayload
            ),
            context: syncContext(ownerUserID: ownerUserID, coupleID: coupleID)
        )

        #expect(result == .terminalFailure("Stale location update rejected"))
        let stored = try await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(stored == newerLocal)
    }

    @Test func staleLocationSuccessDoesNotOverwriteNewerLocalLocation() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = try operation(id: "33333333-3333-3333-3333-333333333333")
        let newerLocal = OwnLocationSnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: LocationPoint(
                latitude: 60,
                longitude: 11,
                capturedAt: Date(timeIntervalSince1970: 300)
            ),
            source: .manualRefresh,
            pendingOperationID: nil,
            updatedAt: Date(timeIntervalSince1970: 301)
        )
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        try await ownLocationStore.save(newerLocal)
        let handler = LatestPartnerLocationPendingOperationHandler(
            gateway: RecordingLocationGateway(
                locationResponse: LatestPartnerLocationUpdateResponse(
                    coupleID: coupleID,
                    userID: ownerUserID,
                    latitude: 59,
                    longitude: 10,
                    accuracyMeters: nil,
                    capturedAt: Date(timeIntervalSince1970: 250),
                    receivedAt: Date(timeIntervalSince1970: 251),
                    updatedAt: Date(timeIntervalSince1970: 252)
                )
            ),
            ownLocationStore: ownLocationStore
        )
        let stalePayload = LatestPartnerLocationOperationPayload(
            coupleID: coupleID,
            location: LocationPoint(
                latitude: 58,
                longitude: 9,
                capturedAt: Date(timeIntervalSince1970: 200)
            ),
            source: .foregroundOpen
        )

        let result = try await handler.send(
            pendingOperation(
                ownerUserID: ownerUserID,
                operation: operation,
                kind: .updateLatestPartnerLocation,
                payload: stalePayload
            ),
            context: syncContext(ownerUserID: ownerUserID, coupleID: coupleID)
        )

        #expect(result == .succeeded)
        let stored = try await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(stored == newerLocal)
    }
}

struct SupabaseLocationGatewayRequestEncodingTests {
    @Test
    func preferenceRequestEncodesNilConsentVersionAsNull() throws {
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let request = UpdateLocationSharingPreferenceRequest(
            payload: LocationSharingPreferenceOperationPayload(
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

@MainActor
struct LocationMapViewModelTests {
    @Test
    func missingSnapshotDoesNotMasqueradeAsRestoredOptOut() async {
        let viewModel = LocationMapViewModel(
            visibilityStore: InMemoryLocationVisibilitySnapshotRepository(),
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: UniqueOperationProvider(),
            locationCapture: StubLocationCapture(error: ForegroundLocationCaptureError.unavailable)
        )

        await viewModel.configure(
            identity: LocationIdentity(
                currentUserID: testUUID("11111111-1111-1111-1111-111111111111"),
                coupleID: testUUID("22222222-2222-2222-2222-222222222222")
            )
        )

        #expect(viewModel.isPresentationReady)
        #expect(viewModel.isSharingLoaded)
        #expect(!viewModel.hasResolvedSharingPreference)
        #expect(!viewModel.sharingEnabled)
    }

    @Test
    func freshViewModelRestoresSharingFromDurableSnapshot() async throws {
        let ownerUserID = testUUID("11111111-1111-1111-1111-111111111111")
        let coupleID = testUUID("22222222-2222-2222-2222-222222222222")
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let viewModel = LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: UniqueOperationProvider(),
            locationCapture: StubLocationCapture(error: ForegroundLocationCaptureError.unavailable)
        )

        await viewModel.configure(
            identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID)
        )

        #expect(viewModel.isPresentationReady)
        #expect(viewModel.isSharingLoaded)
        #expect(viewModel.hasResolvedSharingPreference)
        #expect(viewModel.sharingEnabled)
    }

    @Test
    func restoredSharingDoesNotPromptForSystemPermission() async throws {
        let ownerUserID = testUUID("11111111-1111-1111-1111-111111111111")
        let coupleID = testUUID("22222222-2222-2222-2222-222222222222")
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
        let capture = CountingLocationCapture(authorizationState: .notDetermined)
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let viewModel = LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: UniqueOperationProvider(),
            locationCapture: capture
        )
        await viewModel.configure(
            identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID)
        )

        await viewModel.refreshOwnLocationIfSharingEnabled(
            source: .foregroundOpen,
            mayPromptForAuthorization: false
        )

        #expect(capture.requestCount == 0)
    }

    @Test
    func primerActionCapturesLocationWhenServerPreferenceIsAlreadyEnabled() async throws {
        let ownerUserID = testUUID("11111111-1111-1111-1111-111111111111")
        let coupleID = testUUID("22222222-2222-2222-2222-222222222222")
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let viewModel = LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: pendingStore,
            operationProvider: UniqueOperationProvider(),
            locationCapture: StubLocationCapture(
                location: LocationPoint(
                    latitude: 59.91,
                    longitude: 10.75,
                    capturedAt: Date(timeIntervalSince1970: 101)
                )
            )
        )
        await viewModel.configure(
            identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID)
        )

        await viewModel.promptForCurrentLocation()

        #expect(try await locationWriteCount(pendingStore, ownerUserID: ownerUserID) == 1)
    }

    @Test
    func mapStateRequiresCurrentAndPartnerLocations() throws {
        let current = ownLocationSnapshot()
        let visible = try visibilitySnapshot(
            visibilityState: .visible,
            partnerLocationIsStale: false
        )
        let partnerLocation = try #require(visible.partnerLocation)

        #expect(LocationMapViewModel.resolveMapState(
            visibility: visible,
            ownLocation: current
        ) == .ready(
            current: current.location,
            partner: partnerLocation,
            partnerWasStaleAtLastRefresh: false
        ))
        #expect(LocationMapViewModel.resolveMapState(visibility: visible, ownLocation: nil) == .currentUnknown)
    }

    @Test
    func mapStateKeepsStalePartnerLocationVisible() throws {
        let current = ownLocationSnapshot()
        let veryOld = try visibilitySnapshot(
            visibilityState: .visible,
            partnerLocationIsStale: true,
            partnerLocationCapturedAt: Date(timeIntervalSince1970: 200)
        )
        let partnerLocation = try #require(veryOld.partnerLocation)

        #expect(LocationMapViewModel.resolveMapState(
            visibility: veryOld,
            ownLocation: current
        ) == .ready(
            current: current.location,
            partner: partnerLocation,
            partnerWasStaleAtLastRefresh: true
        ))
    }

    @Test
    func previousIdentityReloadCannotPublishIntoNewCouple() async throws {
        let firstUserID = testUUID("11111111-1111-1111-1111-111111111111")
        let firstCoupleID = testUUID("22222222-2222-2222-2222-222222222222")
        let secondUserID = testUUID("44444444-4444-4444-4444-444444444444")
        let secondCoupleID = testUUID("55555555-5555-5555-5555-555555555555")
        let firstSnapshot = try visibilitySnapshot(
            ownerUserID: firstUserID,
            coupleID: firstCoupleID,
            visibilityState: .visible,
            partnerLocationIsStale: false
        )
        let visibilityStore = IdentitySwitchVisibilityStore(
            suspendedOwnerUserID: firstUserID,
            suspendedSnapshot: firstSnapshot
        )
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        try await ownLocationStore.save(
            OwnLocationSnapshot(
                ownerUserID: firstUserID,
                coupleID: firstCoupleID,
                location: ownLocationSnapshot().location,
                source: .foregroundOpen,
                pendingOperationID: nil,
                updatedAt: Date(timeIntervalSince1970: 101)
            )
        )
        let viewModel = LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: ownLocationStore,
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: UniqueOperationProvider(),
            locationCapture: StubLocationCapture(error: ForegroundLocationCaptureError.unavailable)
        )

        let firstConfiguration = Task {
            await viewModel.configure(
                identity: LocationIdentity(currentUserID: firstUserID, coupleID: firstCoupleID)
            )
        }
        await visibilityStore.waitUntilSuspendedLoadStarts()
        await viewModel.configure(
            identity: LocationIdentity(currentUserID: secondUserID, coupleID: secondCoupleID)
        )
        await visibilityStore.finishSuspendedLoad()
        await firstConfiguration.value

        #expect(viewModel.mapState == .partnerUnknown(.unknown("missing_visibility")))
    }

    @MainActor
    @Test
    func enablingSharingRequestsLocalChangeSync() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let syncRecorder = LocalChangeSyncRecorder()
        let viewModel = LocationMapViewModel(
            visibilityStore: InMemoryLocationVisibilitySnapshotRepository(),
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: FixedOperationProvider(),
            locationCapture: StubLocationCapture(
                location: LocationPoint(
                    latitude: 59.91,
                    longitude: 10.75,
                    capturedAt: Date(timeIntervalSince1970: 100)
                )
            )
        )
        viewModel.setLocalChangeSyncHandler {
            syncRecorder.record()
        }
        await viewModel.configure(identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID))

        await viewModel.setSharingEnabled(true)

        #expect(syncRecorder.callCount == 1)
    }

    @MainActor
    @Test
    func deniedPermissionDoesNotEnableSharingOrQueueOperation() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: pendingStore,
            operationProvider: FixedOperationProvider(),
            locationCapture: StubLocationCapture(error: ForegroundLocationCaptureError.authorizationDenied)
        )
        await viewModel.configure(identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID))

        await viewModel.setSharingEnabled(true)

        #expect(viewModel.sharingEnabled == false)
        #expect(viewModel.notice == .permissionDenied)
        let readyOperations = try await pendingStore.readyOperations(
            ownerUserID: ownerUserID,
            limit: 10,
            now: Date(timeIntervalSince1970: 1_000)
        )
        #expect(readyOperations.isEmpty)
    }

    @Test
    func repeatedShareTapDoesNotStartCompetingLocationRequests() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let locationCapture = SuspendedLocationCapture()
        let viewModel = LocationMapViewModel(
            visibilityStore: InMemoryLocationVisibilitySnapshotRepository(),
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: UniqueOperationProvider(),
            locationCapture: locationCapture
        )
        await viewModel.configure(
            identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID)
        )

        let firstRequest = Task { await viewModel.promptForCurrentLocation() }
        await locationCapture.waitUntilRequested()
        await viewModel.promptForCurrentLocation()

        #expect(locationCapture.requestCount == 1)

        locationCapture.finish(
            with: LocationPoint(
                latitude: 59.91,
                longitude: 10.75,
                capturedAt: Date(timeIntervalSince1970: 100)
            )
        )
        await firstRequest.value
        #expect(viewModel.notice == nil)
    }

    @MainActor
    @Test
    func foregroundRefreshIsThrottledButManualRefreshAlwaysWrites() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = LocationMapViewModel(
            visibilityStore: InMemoryLocationVisibilitySnapshotRepository(),
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: pendingStore,
            operationProvider: UniqueOperationProvider(),
            locationCapture: StubLocationCapture(
                location: LocationPoint(
                    latitude: 59.91,
                    longitude: 10.75,
                    capturedAt: Date()
                )
            )
        )
        await viewModel.configure(identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID))

        // Enabling sharing captures and enqueues the first fix.
        await viewModel.setSharingEnabled(true)
        #expect(try await locationWriteCount(pendingStore, ownerUserID: ownerUserID) == 1)

        // A foreground-open refresh moments later, from the same position, is throttled away.
        await viewModel.refreshOwnLocationIfSharingEnabled(source: .foregroundOpen)
        #expect(try await locationWriteCount(pendingStore, ownerUserID: ownerUserID) == 1)

        // A manual pull-to-refresh always writes, even without moving.
        await viewModel.refreshOwnLocationIfSharingEnabled(source: .manualRefresh)
        #expect(try await locationWriteCount(pendingStore, ownerUserID: ownerUserID) == 2)
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

private actor RecordingLocationGateway: SupabaseLocationGateway {
    private let visibilitySnapshot: LocationVisibilitySnapshot?
    private let preferenceResponse: LocationSharingPreferenceUpdateResponse?
    private let locationResponse: LatestPartnerLocationUpdateResponse?
    private let locationError: (any Error)?
    private(set) var preferencePayloads: [LocationSharingPreferenceOperationPayload] = []
    private(set) var latestLocationPayloads: [LatestPartnerLocationOperationPayload] = []

    init(
        visibilitySnapshot: LocationVisibilitySnapshot? = nil,
        preferenceResponse: LocationSharingPreferenceUpdateResponse? = nil,
        locationResponse: LatestPartnerLocationUpdateResponse? = nil,
        locationError: (any Error)? = nil
    ) {
        self.visibilitySnapshot = visibilitySnapshot
        self.preferenceResponse = preferenceResponse
        self.locationResponse = locationResponse
        self.locationError = locationError
    }

    func loadPartnerLocationVisibility(
        ownerUserID _: UUID,
        coupleID _: UUID
    ) async throws -> LocationVisibilitySnapshot? {
        visibilitySnapshot
    }

    func updateLocationSharingPreference(
        payload: LocationSharingPreferenceOperationPayload,
        operation _: SyncClientOperation
    ) async throws -> LocationSharingPreferenceUpdateResponse? {
        preferencePayloads.append(payload)
        return preferenceResponse
    }

    func updateLatestPartnerLocation(
        payload: LatestPartnerLocationOperationPayload,
        operation _: SyncClientOperation
    ) async throws -> LatestPartnerLocationUpdateResponse? {
        latestLocationPayloads.append(payload)
        if let locationError {
            throw locationError
        }
        return locationResponse
    }
}

private actor IdentitySwitchVisibilityStore: LocationVisibilitySnapshotPersisting {
    private let suspendedOwnerUserID: UUID
    private let suspendedSnapshot: LocationVisibilitySnapshot
    private var loadContinuation: CheckedContinuation<LocationVisibilitySnapshot?, Never>?

    init(
        suspendedOwnerUserID: UUID,
        suspendedSnapshot: LocationVisibilitySnapshot
    ) {
        self.suspendedOwnerUserID = suspendedOwnerUserID
        self.suspendedSnapshot = suspendedSnapshot
    }

    func save(_ snapshot: LocationVisibilitySnapshot) async throws {}

    func load(ownerUserID: UUID, coupleID _: UUID) async throws -> LocationVisibilitySnapshot? {
        guard ownerUserID == suspendedOwnerUserID else { return nil }
        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func setViewerSharingEnabled(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        updatedAt: Date
    ) async throws {}

    func delete(ownerUserID: UUID, coupleID: UUID) async throws {}

    func waitUntilSuspendedLoadStarts() async {
        while loadContinuation == nil {
            await Task.yield()
        }
    }

    func finishSuspendedLoad() {
        loadContinuation?.resume(returning: suspendedSnapshot)
        loadContinuation = nil
    }
}

private struct StaleLocationError: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private final class LocalChangeSyncRecorder {
    private(set) var callCount = 0

    func record() {
        callCount += 1
    }
}

@MainActor
private final class FixedOperationProvider: SyncClientOperationProviding {
    private var sequence: Int64 = 0
    private let clientID = testUUID("99999999-9999-9999-9999-999999999999")

    func makeOperation() -> SyncClientOperation {
        sequence += 1
        return SyncClientOperation(
            id: testUUID("88888888-8888-8888-8888-888888888888"),
            clientID: clientID,
            clientSequence: sequence,
            localCreatedAt: Date(timeIntervalSince1970: TimeInterval(sequence))
        )
    }
}

@MainActor
private final class UniqueOperationProvider: SyncClientOperationProviding {
    private var sequence: Int64 = 0
    private let clientID = testUUID("99999999-9999-9999-9999-999999999999")

    func makeOperation() -> SyncClientOperation {
        sequence += 1
        return SyncClientOperation(
            id: UUID(),
            clientID: clientID,
            clientSequence: sequence,
            localCreatedAt: Date(timeIntervalSince1970: TimeInterval(sequence))
        )
    }
}

private func locationWriteCount(
    _ store: InMemoryPendingSyncOperationRepository,
    ownerUserID: UUID
) async throws -> Int {
    try await store.readyOperations(ownerUserID: ownerUserID, limit: 100, now: Date())
        .filter { $0.operationKind == .updateLatestPartnerLocation }
        .count
}

@MainActor
private final class StubLocationCapture: ForegroundLocationCapturing {
    private let location: LocationPoint?
    private let error: (any Error)?

    init(location: LocationPoint) {
        self.location = location
        error = nil
    }

    init(error: any Error) {
        location = nil
        self.error = error
    }

    func captureCurrentLocation() async throws -> LocationPoint {
        if let location {
            return location
        }
        throw error ?? ForegroundLocationCaptureError.unavailable
    }
}

@MainActor
private final class SuspendedLocationCapture: ForegroundLocationCapturing {
    let authorizationState: ForegroundLocationAuthorizationState = .authorized
    private var continuation: CheckedContinuation<LocationPoint, Never>?
    private(set) var requestCount = 0

    func captureCurrentLocation() async throws -> LocationPoint {
        requestCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilRequested() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func finish(with location: LocationPoint) {
        continuation?.resume(returning: location)
        continuation = nil
    }
}

@MainActor
private final class CountingLocationCapture: ForegroundLocationCapturing {
    let authorizationState: ForegroundLocationAuthorizationState
    private(set) var requestCount = 0

    init(authorizationState: ForegroundLocationAuthorizationState) {
        self.authorizationState = authorizationState
    }

    // swiftlint:disable:next async_without_await
    func captureCurrentLocation() async throws -> LocationPoint {
        requestCount += 1
        throw ForegroundLocationCaptureError.unavailable
    }
}

private struct StaticPushAuthorization: PushAuthorizationProviding {
    let isNotDeterminedValue: Bool

    init(isNotDetermined: Bool) {
        isNotDeterminedValue = isNotDetermined
    }

    // swiftlint:disable async_without_await
    func isNotDetermined() async -> Bool { isNotDeterminedValue }
    func requestAuthorizationIfNeeded() async -> Bool { true }
    func isDenied() async -> Bool { false }
    // swiftlint:enable async_without_await
}

@MainActor
private final class SequencedPushAuthorization: PushAuthorizationProviding {
    private var evaluationCount = 0
    private var firstEvaluationContinuation: CheckedContinuation<Bool, Never>?
    private var firstEvaluationStartWaiters: [CheckedContinuation<Void, Never>] = []

    func isNotDetermined() async -> Bool {
        evaluationCount += 1
        guard evaluationCount == 1 else {
            return true
        }

        let waiters = firstEvaluationStartWaiters
        firstEvaluationStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            firstEvaluationContinuation = continuation
        }
    }

    func waitUntilFirstEvaluationStarts() async {
        guard evaluationCount == 0 else {
            return
        }
        await withCheckedContinuation { continuation in
            firstEvaluationStartWaiters.append(continuation)
        }
    }

    func finishFirstEvaluation() {
        firstEvaluationContinuation?.resume(returning: true)
        firstEvaluationContinuation = nil
    }

    // swiftlint:disable async_without_await
    func requestAuthorizationIfNeeded() async -> Bool { true }
    func isDenied() async -> Bool { false }
    // swiftlint:enable async_without_await
}

private func visibilitySnapshot(
    ownerUserID: UUID = testUUID("11111111-1111-1111-1111-111111111111"),
    coupleID: UUID = testUUID("22222222-2222-2222-2222-222222222222"),
    visibilityState: PartnerLocationVisibilityState,
    partnerLocationIsStale: Bool,
    partnerLocationCapturedAt: Date = Date(timeIntervalSince1970: 200)
) throws -> LocationVisibilitySnapshot {
    LocationVisibilitySnapshot(
        ownerUserID: ownerUserID,
        coupleID: coupleID,
        viewerUserID: ownerUserID,
        partnerUserID: testUUID("33333333-3333-3333-3333-333333333333"),
        visibilityState: visibilityState,
        viewerSharingEnabled: true,
        partnerSharingEnabled: true,
        partnerLocation: LocationPoint(
            latitude: 69.96,
            longitude: 23.27,
            accuracyMeters: 20,
            capturedAt: partnerLocationCapturedAt,
            updatedAt: Date(timeIntervalSince1970: 201)
        ),
        partnerLocationIsStale: partnerLocationIsStale,
        updatedAt: Date(timeIntervalSince1970: 202),
        refreshedAt: Date(timeIntervalSince1970: 203)
    )
}

private func ownLocationSnapshot() -> OwnLocationSnapshot {
    OwnLocationSnapshot(
        ownerUserID: testUUID("11111111-1111-1111-1111-111111111111"),
        coupleID: testUUID("22222222-2222-2222-2222-222222222222"),
        location: LocationPoint(
            latitude: 59,
            longitude: 10,
            capturedAt: Date(timeIntervalSince1970: 100)
        ),
        source: .foregroundOpen,
        pendingOperationID: nil,
        updatedAt: Date(timeIntervalSince1970: 101)
    )
}

private func testUUID(_ rawValue: String) -> UUID {
    guard let uuid = UUID(uuidString: rawValue) else {
        preconditionFailure("Invalid test UUID: \(rawValue)")
    }
    return uuid
}

private func operation(id: String) throws -> SyncClientOperation {
    SyncClientOperation(
        id: try #require(UUID(uuidString: id)),
        clientID: try #require(UUID(uuidString: "99999999-9999-9999-9999-999999999999")),
        clientSequence: 1,
        localCreatedAt: Date(timeIntervalSince1970: 100)
    )
}

private func pendingOperation<Payload: Encodable>(
    ownerUserID: UUID,
    operation: SyncClientOperation,
    kind: SyncPendingOperationKind,
    payload: Payload
) throws -> PendingSyncOperationSnapshot {
    PendingSyncOperationSnapshot(
        ownerUserID: ownerUserID,
        operation: operation,
        operationKind: kind,
        idempotencyScope: "test:\(operation.id.uuidString)",
        requestHash: nil,
        requestData: try JSONEncoder().encode(payload),
        status: .queued,
        attemptCount: 0,
        lastAttemptAt: nil,
        nextRetryAt: nil,
        lastError: nil,
        completedAt: nil
    )
}

private func syncContext(ownerUserID: UUID, coupleID: UUID) -> SyncContext {
    SyncContext(
        session: SyncSession(userID: ownerUserID, activeCoupleID: coupleID),
        reason: .manualRefresh,
        stateStore: InMemorySyncStateRepository(),
        pendingOperationStore: InMemoryPendingSyncOperationRepository()
    )
}
