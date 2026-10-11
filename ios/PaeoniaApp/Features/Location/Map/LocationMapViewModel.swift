import Foundation
import Observation

@MainActor
@Observable
final class LocationMapViewModel: PresentationReadinessProviding {
    enum Notice: Equatable {
        case saveFailed
        case permissionDenied
        case locationUnavailable
    }

    private enum Constants {
        static let consentVersion = "location-sharing-v1"
    }

    private enum LocationOperationAbort: Error {
        /// The account or couple changed, or a newer sharing choice replaced
        /// this operation. Whatever replaced it decides what gets stored.
        case superseded
    }

    private enum LocationOperationKind {
        case sharingChange
        case refresh
    }

    private struct LocationOperation {
        let id: UUID
        let kind: LocationOperationKind
    }

    private let visibilityStore: any LocationVisibilitySnapshotPersisting
    private let ownLocationStore: any OwnLocationSnapshotPersisting
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private let operationProvider: any SyncClientOperationProviding
    private let locationCapture: any ForegroundLocationCapturing
    private let encoder = JSONEncoder()
    private var localChangeSyncHandler: (@MainActor () async -> Void)?

    private var identity = LocationIdentity(currentUserID: nil, coupleID: nil)
    private var reloadGeneration = 0
    private var activeOperation: LocationOperation?
    private var storeChangesTask: Task<Void, Never>?
    private var reloadsInFlight = 0
    private var storeChangedDuringReload = false
    private var locatingCount = 0
    /// The last stored state, kept so a permission or "finding you" change can
    /// redraw the map card without another store read.
    private var loadedVisibility: LocationVisibilitySnapshot?
    private var loadedOwnLocation: OwnLocationSnapshot?
    private var hasLoadedSnapshots = false

    private(set) var mapState: CoupleMapState = .loading
    private(set) var isPresentationReady = false
    private(set) var sharingEnabled = false
    private(set) var isSharingLoaded = false
    private(set) var hasResolvedSharingPreference = false
    private(set) var notice: Notice?
    /// iOS location permission as of the last check. Stored so SwiftUI can
    /// follow it; refreshed on every reload, refresh, and sharing change.
    private(set) var authorizationState: ForegroundLocationAuthorizationState = .notDetermined

    /// True while a sharing choice is being saved. The settings switch stays
    /// disabled so a second flip cannot be dropped halfway.
    var isUpdatingSharing: Bool {
        activeOperation?.kind == .sharingChange
    }

    init(
        visibilityStore: (any LocationVisibilitySnapshotPersisting)? = nil,
        ownLocationStore: (any OwnLocationSnapshotPersisting)? = nil,
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        locationCapture: (any ForegroundLocationCapturing)? = nil
    ) {
        let defaultStores = Self.makeDefaultStores(
            needsVisibilityStore: visibilityStore == nil,
            needsOwnLocationStore: ownLocationStore == nil,
            needsPendingOperationStore: pendingOperationStore == nil
        )
        self.visibilityStore = visibilityStore
            ?? defaultStores?.visibilityStore
            ?? InMemoryLocationVisibilitySnapshotRepository()
        self.ownLocationStore = ownLocationStore
            ?? defaultStores?.ownLocationStore
            ?? InMemoryOwnLocationSnapshotRepository()
        self.pendingOperationStore = pendingOperationStore
            ?? defaultStores?.pendingOperationStore
            ?? InMemoryPendingSyncOperationRepository()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.locationCapture = locationCapture ?? ForegroundLocationCaptureService()
        authorizationState = self.locationCapture.authorizationState
    }

    func configure(identity: LocationIdentity) async {
        observeStoreChanges()
        guard self.identity != identity else {
            await reload()
            return
        }

        // The suspended request belongs to the previous account/couple. Its
        // identity checks prevent it from committing when it resumes, while the
        // token comparison in `defer` prevents it from clearing a newer request.
        activeOperation = nil
        self.identity = identity
        reloadGeneration &+= 1
        resetPresentation()
        notice = nil
        await reload()
    }

    /// Re-reads the store whenever the live feed or a local write changes the
    /// partner's location state or our own location. Starts once and stops when
    /// the view model is gone.
    private func observeStoreChanges() {
        guard storeChangesTask == nil else { return }
        let changes = LocalStoreChanges.changes(in: .locationVisibility, .ownLocation)
        storeChangesTask = Task { [weak self] in
            for await change in changes {
                guard let self else { return }
                guard change.ownerUserID == identity.currentUserID else { continue }
                await reloadAfterStoreChange()
            }
        }
    }

    /// A store change must not cancel a reload that a caller is awaiting, or that
    /// caller returns before the state is set. It queues one more reload instead.
    private func reloadAfterStoreChange() async {
        if reloadsInFlight > 0 {
            storeChangedDuringReload = true
        } else {
            await reload()
        }
    }

    func setLocalChangeSyncHandler(_ handler: (@MainActor () async -> Void)?) {
        localChangeSyncHandler = handler
    }

    func reload() async {
        reloadsInFlight += 1
        await performReload()
        reloadsInFlight -= 1
        if reloadsInFlight == 0, storeChangedDuringReload {
            storeChangedDuringReload = false
            await reload()
        }
    }

    private func performReload() async {
        reloadGeneration &+= 1
        let activeReloadGeneration = reloadGeneration
        let requestedIdentity = identity

        refreshAuthorizationState()
        guard let currentUserID = requestedIdentity.currentUserID,
              let coupleID = requestedIdentity.coupleID
        else {
            resetPresentation()
            return
        }

        do {
            let visibility = try await visibilityStore.load(ownerUserID: currentUserID, coupleID: coupleID)
            let ownLocation = try await ownLocationStore.load(ownerUserID: currentUserID, coupleID: coupleID)
            guard identity == requestedIdentity,
                  reloadGeneration == activeReloadGeneration
            else {
                return
            }

            applyLoaded(visibility: visibility, ownLocation: ownLocation)
        } catch {
            guard identity == requestedIdentity,
                  reloadGeneration == activeReloadGeneration
            else {
                return
            }

            hasLoadedSnapshots = false
            mapState = .partnerUnknown(.unknown("local_load_failed"))
            isPresentationReady = true
            // Local-first controls remain available offline. Automatic priming
            // uses the separate resolved flag and stays quiet until a cached or
            // server snapshot establishes the actual preference.
            isSharingLoaded = true
            hasResolvedSharingPreference = false
        }
    }

    private func resetPresentation() {
        loadedVisibility = nil
        loadedOwnLocation = nil
        hasLoadedSnapshots = false
        mapState = .loading
        isPresentationReady = false
        sharingEnabled = false
        isSharingLoaded = false
        hasResolvedSharingPreference = false
    }

    private func applyLoaded(visibility: LocationVisibilitySnapshot?, ownLocation: OwnLocationSnapshot?) {
        // Keep an in-flight opt-in/opt-out stable while a scene-activation
        // reload runs behind the system location sheet.
        if !isUpdatingSharing {
            sharingEnabled = visibility?.viewerSharingEnabled ?? false
        }
        isSharingLoaded = true
        hasResolvedSharingPreference = visibility != nil
        loadedVisibility = visibility
        loadedOwnLocation = ownLocation
        hasLoadedSnapshots = true
        publishMapState()
        isPresentationReady = true
    }

    func setSharingEnabled(_ enabled: Bool) async {
        refreshAuthorizationState()
        guard enabled != sharingEnabled,
              let currentUserID = identity.currentUserID,
              let coupleID = identity.coupleID,
              let operationID = beginOperation(.sharingChange)
        else {
            return
        }

        let operationIdentity = identity
        defer { finishOperation(operationID) }
        // Read before the capture, which may show the system prompt and change it.
        let permissionWasUndecided = authorizationState == .notDetermined

        let previousValue = sharingEnabled
        sharingEnabled = enabled
        isSharingLoaded = true
        hasResolvedSharingPreference = true

        do {
            try await persistSharingChange(
                ownerUserID: currentUserID,
                coupleID: coupleID,
                enabled: enabled,
                operationID: operationID,
                operationIdentity: operationIdentity
            )

            await syncAfterLocalChange()
            try requireCurrent(operationID, identity: operationIdentity)
            await reload()
        } catch LocationOperationAbort.superseded {
            return
        } catch {
            await restoreSharingChange(
                previousValue: previousValue,
                operationIdentity: operationIdentity,
                permissionWasUndecided: permissionWasUndecided,
                error: error
            )
        }
    }

    func promptForCurrentLocation() async {
        guard activeOperation == nil else { return }

        if sharingEnabled {
            await refreshOwnLocationIfSharingEnabled(source: .manualRefresh)
        } else {
            await setSharingEnabled(true)
        }
    }

    func refreshOwnLocationIfSharingEnabled(
        source: LocationSharingSource,
        mayPromptForAuthorization: Bool = true
    ) async {
        // Scene activation lands here, so this is also where a permission
        // change made in the Settings app reaches the map card.
        refreshAuthorizationState()
        guard mayPromptForAuthorization || authorizationState == .authorized else {
            return
        }

        guard sharingEnabled,
              let currentUserID = identity.currentUserID,
              let coupleID = identity.coupleID,
              let operationID = beginOperation(.refresh)
        else {
            return
        }

        let operationIdentity = identity
        defer { finishOperation(operationID) }
        let ensureCurrent = { [self] in
            try requireCurrent(operationID, identity: operationIdentity)
        }

        do {
            try await captureAndQueueOwnLocation(
                source: source,
                ownerUserID: currentUserID,
                coupleID: coupleID,
                ensureCurrent: ensureCurrent
            )
        } catch LocationOperationAbort.superseded {
            return
        } catch {
            guard identity == operationIdentity else { return }
            // An automatic refresh on app open must not raise an error banner
            // every time the phone is indoors. The map card shows the state.
            guard source != .foregroundOpen else { return }
            notice = notice(for: error)
        }
    }

    private func captureAndQueueOwnLocation(
        source: LocationSharingSource,
        ownerUserID: UUID,
        coupleID: UUID,
        ensureCurrent: () throws -> Void
    ) async throws {
        let location = try await captureCurrentLocation()
        try ensureCurrent()
        guard try await shouldSendLocation(
            location,
            source: source,
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            ensureCurrent: ensureCurrent
        ) else { return }

        try await saveAndEnqueueOwnLocation(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: location,
            source: source,
            ensureCurrent: ensureCurrent
        )

        await syncAfterLocalChange()
        try ensureCurrent()
        await reload()
    }

    func dismissNotice() {
        notice = nil
    }

    private func enqueueLocationPreference(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        source: LocationSharingSource
    ) async throws {
        let operation = operationProvider.makeOperation()
        let payload = LocationSharingPreferenceOperationPayload(
            coupleID: coupleID,
            isEnabled: isEnabled,
            consentVersion: isEnabled ? Constants.consentVersion : nil,
            source: source
        )
        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .updateLocationSharingPreference,
                idempotencyScope: [
                    "location-preference",
                    coupleID.uuidString.lowercased(),
                    operation.id.uuidString.lowercased(),
                ].joined(separator: ":"),
                requestData: try encoder.encode(payload)
            )
        )
    }

    private func persistSharingChange(
        ownerUserID: UUID,
        coupleID: UUID,
        enabled: Bool,
        operationID: UUID,
        operationIdentity: LocationIdentity
    ) async throws {
        let ensureCurrent = { [self] in
            try requireCurrent(operationID, identity: operationIdentity)
        }
        let capturedLocation: LocationPoint?
        if enabled {
            do {
                capturedLocation = try await captureCurrentLocation()
            } catch ForegroundLocationCaptureError.unavailable
                where locationCapture.authorizationState == .authorized {
                // The durable sharing choice does not depend on one GPS fix.
                // A later foreground refresh can fill in the current location,
                // and the map card offers a retry meanwhile.
                capturedLocation = nil
                notice = .locationUnavailable
            }
        } else {
            capturedLocation = nil
        }
        try ensureCurrent()

        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: enabled,
            updatedAt: Date()
        )
        try ensureCurrent()

        try await enqueueLocationPreference(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: enabled,
            source: .settingsToggle
        )
        try ensureCurrent()

        if let capturedLocation {
            do {
                try await saveAndEnqueueOwnLocation(
                    ownerUserID: ownerUserID,
                    coupleID: coupleID,
                    location: capturedLocation,
                    source: .settingsToggle,
                    ensureCurrent: ensureCurrent
                )
            } catch LocationOperationAbort.superseded {
                throw LocationOperationAbort.superseded
            } catch {
                // The preference is already safely cached and queued. Keep the
                // user's choice even if saving this first fix fails; a later
                // foreground refresh can try the latest location again.
                try ensureCurrent()
                notice = .saveFailed
            }
        } else {
            try? await ownLocationStore.delete(ownerUserID: ownerUserID, coupleID: coupleID)
            await dropQueuedLocationUploads(
                ownerUserID: ownerUserID,
                keeping: nil,
                reason: "cancelled because location sharing was turned off"
            )
        }
        try ensureCurrent()
    }

    /// Drops queued location uploads that have not started sending, except
    /// `keeping`. Used for two cases. A location queued before an opt-out must
    /// not reach the server after it (the outbox can send it first while the
    /// opt-out waits for a retry). And only the latest position matters, so a
    /// newer location replaces older ones instead of replaying each of them.
    private func dropQueuedLocationUploads(ownerUserID: UUID, keeping kept: UUID?, reason: String) async {
        let queued = (try? await pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .updateLatestPartnerLocation
        )) ?? []
        for operation in queued where operation.status != .sending && operation.operation.id != kept {
            try? await pendingOperationStore.markTerminalFailure(
                clientOperationID: operation.operation.id,
                errorDescription: reason,
                at: Date()
            )
        }
    }

    private func restoreSharingChange(
        previousValue: Bool,
        operationIdentity: LocationIdentity,
        permissionWasUndecided: Bool,
        error: any Error
    ) async {
        guard identity == operationIdentity,
              let ownerUserID = operationIdentity.currentUserID,
              let coupleID = operationIdentity.coupleID
        else { return }
        refreshAuthorizationState()
        sharingEnabled = previousValue
        // Nothing was queued for this value, so it is not waiting on the server.
        try? await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: previousValue,
            updatedAt: Date(),
            isPendingConfirmation: false
        )
        guard identity == operationIdentity else { return }
        // Tapping "Don't Allow" on the system prompt is a choice, not an
        // error. The map card already shows how to turn location on later.
        let declinedSystemPrompt = permissionWasUndecided
            && (error as? ForegroundLocationCaptureError) == .authorizationDenied
        if !declinedSystemPrompt {
            notice = notice(for: error)
        }
        await reload()
    }

    private func shouldSendLocation(
        _ location: LocationPoint,
        source: LocationSharingSource,
        ownerUserID: UUID,
        coupleID: UUID,
        ensureCurrent: () throws -> Void
    ) async throws -> Bool {
        // A routine foreground refresh only writes when the fix is stale or the
        // user moved; explicit refreshes always write.
        guard source == .foregroundOpen else { return true }

        let lastSent = (try? await ownLocationStore.load(
            ownerUserID: ownerUserID,
            coupleID: coupleID
        ))?.location
        try ensureCurrent()
        return RoutineLocationThrottle.shouldSend(
            lastSent: lastSent,
            current: location,
            now: Date()
        )
    }

    /// Starts an operation, or returns nil when it must not run now. A sharing
    /// choice replaces a running refresh: turning sharing off must never wait
    /// for (or be dropped behind) a GPS fix, and the replaced refresh stops
    /// before it writes anything.
    private func beginOperation(_ kind: LocationOperationKind) -> UUID? {
        if let activeOperation {
            guard kind == .sharingChange, activeOperation.kind == .refresh else {
                return nil
            }
        }
        let operation = LocationOperation(id: UUID(), kind: kind)
        activeOperation = operation
        return operation.id
    }

    private func finishOperation(_ operationID: UUID) {
        if activeOperation?.id == operationID {
            activeOperation = nil
        }
    }

    private func requireCurrent(_ operationID: UUID, identity expectedIdentity: LocationIdentity) throws {
        guard identity == expectedIdentity, activeOperation?.id == operationID else {
            throw LocationOperationAbort.superseded
        }
    }

    private func captureCurrentLocation() async throws -> LocationPoint {
        locatingCount += 1
        publishMapState()
        defer {
            locatingCount -= 1
            refreshAuthorizationState()
            publishMapState()
        }
        return try await locationCapture.captureCurrentLocation()
    }

    private func refreshAuthorizationState() {
        let state = locationCapture.authorizationState
        guard state != authorizationState else { return }
        authorizationState = state
        publishMapState()
    }

    private func publishMapState() {
        guard hasLoadedSnapshots else { return }
        mapState = Self.resolveMapState(
            visibility: loadedVisibility,
            ownLocation: loadedOwnLocation,
            authorization: authorizationState,
            isLocating: locatingCount > 0
        )
    }

    private func saveAndEnqueueOwnLocation(
        ownerUserID: UUID,
        coupleID: UUID,
        location: LocationPoint,
        source: LocationSharingSource,
        ensureCurrent: () throws -> Void
    ) async throws {
        let operation = operationProvider.makeOperation()
        let previousSnapshot = try await ownLocationStore.load(
            ownerUserID: ownerUserID,
            coupleID: coupleID
        )
        // Checked right before each write, so a refresh that a newer sharing
        // choice replaced never stores or queues a location after an opt-out.
        try ensureCurrent()
        try await ownLocationStore.save(
            OwnLocationSnapshot(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                location: location,
                source: source,
                pendingOperationID: operation.id,
                updatedAt: Date()
            )
        )

        do {
            try ensureCurrent()
            try await enqueueReplacingOlderLocations(
                latestLocationRequest(
                    ownerUserID: ownerUserID,
                    coupleID: coupleID,
                    location: location,
                    source: source,
                    operation: operation
                )
            )
        } catch LocationOperationAbort.superseded {
            // The operation that replaced this one owns the stored state now.
            throw LocationOperationAbort.superseded
        } catch {
            // A fresh snapshot without its matching pending operation would
            // make the foreground throttle believe this location was queued.
            // Restore the last durable state so the next refresh retries.
            if let previousSnapshot {
                try? await ownLocationStore.save(previousSnapshot)
            } else {
                try? await ownLocationStore.delete(
                    ownerUserID: ownerUserID,
                    coupleID: coupleID
                )
            }
            throw error
        }
    }

    /// Queues a location upload and drops older queued ones, but only after
    /// the newer one is safely queued.
    private func enqueueReplacingOlderLocations(_ request: PendingSyncOperationRequest) async throws {
        try await pendingOperationStore.enqueue(request)
        await dropQueuedLocationUploads(
            ownerUserID: request.ownerUserID,
            keeping: request.operation.id,
            reason: "replaced by a newer location"
        )
    }

    private func latestLocationRequest(
        ownerUserID: UUID,
        coupleID: UUID,
        location: LocationPoint,
        source: LocationSharingSource,
        operation: SyncClientOperation
    ) throws -> PendingSyncOperationRequest {
        let payload = LatestPartnerLocationOperationPayload(
            coupleID: coupleID,
            location: location,
            source: source
        )
        return PendingSyncOperationRequest(
            ownerUserID: ownerUserID,
            operation: operation,
            operationKind: .updateLatestPartnerLocation,
            idempotencyScope: [
                "latest-location",
                coupleID.uuidString.lowercased(),
                operation.id.uuidString.lowercased(),
            ].joined(separator: ":"),
            requestData: try encoder.encode(payload)
        )
    }

    private func syncAfterLocalChange() async {
        await localChangeSyncHandler?()
    }

    private func notice(for error: any Error) -> Notice {
        if let locationError = error as? ForegroundLocationCaptureError {
            switch locationError {
            case .authorizationDenied:
                return .permissionDenied
            case .unavailable:
                return .locationUnavailable
            }
        }

        return .saveFailed
    }

    private static func makeDefaultStores(
        needsVisibilityStore: Bool,
        needsOwnLocationStore: Bool,
        needsPendingOperationStore: Bool
    ) -> (
        visibilityStore: any LocationVisibilitySnapshotPersisting,
        ownLocationStore: any OwnLocationSnapshotPersisting,
        pendingOperationStore: any PendingSyncOperationPersisting
    )? {
        guard needsVisibilityStore || needsOwnLocationStore || needsPendingOperationStore else {
            return nil
        }

        guard let localStore = PaeoniaLocalStore.shared else {
            return nil
        }

        return (
            SwiftDataLocationVisibilitySnapshotRepository(container: localStore.container),
            SwiftDataOwnLocationSnapshotRepository(container: localStore.container),
            SwiftDataPendingSyncOperationRepository(container: localStore.container)
        )
    }
}
