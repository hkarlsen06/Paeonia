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

    enum LocationOperationAbort: Error {
        /// The account or couple changed, or a newer sharing choice replaced
        /// this operation. Whatever replaced it decides what gets stored.
        case superseded
    }

    enum LocationOperationKind {
        case sharingChange
        case refresh
    }

    private struct LocationOperation {
        let id: UUID
        let kind: LocationOperationKind
    }

    let visibilityStore: any LocationVisibilitySnapshotPersisting
    let ownLocationStore: any OwnLocationSnapshotPersisting
    let pendingOperationStore: any PendingSyncOperationPersisting
    let operationProvider: any SyncClientOperationProviding
    let locationCapture: any ForegroundLocationCapturing
    let encoder = JSONEncoder()
    private var localChangeSyncHandler: (@MainActor () async -> Void)?

    private(set) var identity = LocationIdentity(currentUserID: nil, coupleID: nil)
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
    @ObservationIgnored var pauseExpiryTask: Task<Void, Never>?

    private(set) var mapState: CoupleMapState = .loading
    private(set) var isPresentationReady = false
    private(set) var sharingEnabled = false
    /// When your pause ends, while sharing is on but paused. The partner never gets this time.
    /// Only `trackPause` (in `LocationMapViewModel+Pause.swift`) sets it.
    var pausedUntil: Date?
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

    /// Sharing is on and paused, and the pause has not reached its time on this
    /// phone's clock. Nothing is sent meanwhile.
    var isSharingPaused: Bool {
        sharingEnabled && (pausedUntil ?? .distantPast) > Date()
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
            ?? InMemoryLocationVisibilityRepository()
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
        trackPause(until: nil)
        isSharingLoaded = false
        hasResolvedSharingPreference = false
    }

    private func applyLoaded(visibility: LocationVisibilitySnapshot?, ownLocation: OwnLocationSnapshot?) {
        // Keep an in-flight opt-in/opt-out stable while a scene-activation
        // reload runs behind the system location sheet.
        if !isUpdatingSharing {
            sharingEnabled = visibility?.viewerSharingEnabled ?? false
            trackPause(until: visibility?.pausedUntil(at: Date()))
        }
        isSharingLoaded = true
        hasResolvedSharingPreference = visibility != nil
        loadedVisibility = visibility
        loadedOwnLocation = ownLocation
        hasLoadedSnapshots = true
        publishMapState()
        isPresentationReady = true
    }

    func promptForCurrentLocation() async {
        guard activeOperation == nil else { return }

        if isSharingPaused {
            await resumeSharing()
        } else if sharingEnabled {
            await refreshOwnLocationIfSharingEnabled(source: .manualRefresh)
        } else {
            await setSharingEnabled(true)
        }
    }

    func dismissNotice() {
        notice = nil
    }

    func refreshAuthorizationState() {
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

    func syncAfterLocalChange() async {
        await localChangeSyncHandler?()
    }
}

// MARK: Operations and shared helpers

extension LocationMapViewModel {
    /// Starts an operation, or returns nil when it must not run now. A sharing
    /// choice replaces a running refresh: turning sharing off must never wait
    /// for (or be dropped behind) a GPS fix, and the replaced refresh stops
    /// before it writes anything.
    func beginOperation(_ kind: LocationOperationKind) -> UUID? {
        if let activeOperation {
            guard kind == .sharingChange, activeOperation.kind == .refresh else {
                return nil
            }
        }
        let operation = LocationOperation(id: UUID(), kind: kind)
        activeOperation = operation
        return operation.id
    }

    func finishOperation(_ operationID: UUID) {
        if activeOperation?.id == operationID {
            activeOperation = nil
        }
    }

    func requireCurrent(_ operationID: UUID, identity expectedIdentity: LocationIdentity) throws {
        guard identity == expectedIdentity, activeOperation?.id == operationID else {
            throw LocationOperationAbort.superseded
        }
    }

    func captureCurrentLocation() async throws -> LocationPoint {
        locatingCount += 1
        publishMapState()
        defer {
            locatingCount -= 1
            refreshAuthorizationState()
            publishMapState()
        }
        return try await locationCapture.captureCurrentLocation()
    }

    func notice(for error: any Error) -> Notice {
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

    /// Shows a sharing choice before it is saved, so the switch follows the tap.
    func showSharingChoice(_ enabled: Bool) {
        sharingEnabled = enabled
        isSharingLoaded = true
        hasResolvedSharingPreference = true
    }

    /// Puts the switch back after a sharing choice could not be saved.
    func restoreSharingValue(_ enabled: Bool) {
        sharingEnabled = enabled
    }

    func show(_ newNotice: Notice) {
        notice = newNotice
    }
}

extension LocationMapViewModel {
    private struct DefaultStores {
        let visibilityStore: any LocationVisibilitySnapshotPersisting
        let ownLocationStore: any OwnLocationSnapshotPersisting
        let pendingOperationStore: any PendingSyncOperationPersisting
    }

    private static func makeDefaultStores(
        needsVisibilityStore: Bool,
        needsOwnLocationStore: Bool,
        needsPendingOperationStore: Bool
    ) -> DefaultStores? {
        guard needsVisibilityStore || needsOwnLocationStore || needsPendingOperationStore else {
            return nil
        }

        guard let localStore = PaeoniaLocalStore.shared else {
            return nil
        }

        return DefaultStores(
            visibilityStore: SwiftDataLocationVisibilityRepository(container: localStore.container),
            ownLocationStore: SwiftDataOwnLocationSnapshotRepository(container: localStore.container),
            pendingOperationStore: SwiftDataPendingSyncOperationRepository(container: localStore.container)
        )
    }
}
