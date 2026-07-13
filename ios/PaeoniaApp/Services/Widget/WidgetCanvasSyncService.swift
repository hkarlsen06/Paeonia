import CoreGraphics
import Foundation
import PencilKit
#if DEBUG
import OSLog
#endif

/// Identity needed to label a synced drawing with the right nickname.
nonisolated struct WidgetSyncIdentity: Hashable, Sendable {
    let currentUserID: UUID?
    let currentDisplayName: String?
    let partnerDisplayName: String?
}

/// Downloads a payload object. Abstracted so the sync pipeline is testable
/// without the network.
nonisolated protocol WidgetPayloadDownloading: Sendable {
    func download(from url: URL) async throws -> Data
}

struct URLSessionWidgetPayloadDownloader: WidgetPayloadDownloading {
    func download(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Pulls the couple's latest active revision and shows it locally (widget +
/// in-app canvas). This is what makes a partner's drawing actually appear.
nonisolated protocol WidgetCanvasSyncing: Sendable {
    func sync(identity: WidgetSyncIdentity) async
    func hideForPrivacy() async
    func clearForPrivacy() async
}

actor WidgetCanvasSyncService: WidgetCanvasSyncing {
    private let gateway: any WidgetCanvasGateway
    private let localStore: any WidgetCanvasManaging
    private let downloader: any WidgetPayloadDownloading
    private let pendingStore: WidgetPendingUploadStore
    private let pendingUploader: (any WidgetCanvasUploading)?
    private let defaults: UserDefaults
    private nonisolated static let lastSyncedKey = "paeonia.widgetCanvas.lastSyncedRevisionID"
    private var inFlightSync: (identity: WidgetSyncIdentity, task: Task<Void, Never>)?
    private var pendingRerunIdentities: Set<WidgetSyncIdentity> = []

    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "WidgetSync"
    )
    #endif

    init(
        gateway: any WidgetCanvasGateway,
        localStore: any WidgetCanvasManaging,
        downloader: any WidgetPayloadDownloading = URLSessionWidgetPayloadDownloader(),
        pendingStore: WidgetPendingUploadStore = .shared,
        pendingUploader: (any WidgetCanvasUploading)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.gateway = gateway
        self.localStore = localStore
        self.downloader = downloader
        self.pendingStore = pendingStore
        self.pendingUploader = pendingUploader
        self.defaults = defaults
    }

    func sync(identity: WidgetSyncIdentity) async {
        // A matching run is already going. It may have already read the canvas state, so
        // simply awaiting it could miss a revision committed after that read. Ask the
        // running pass for one trailing re-run (all duplicates collapse into a single
        // re-run) and wait for that pass to finish. A different identity still runs on
        // its own, independently.
        if let inFlightSync, inFlightSync.identity == identity {
            pendingRerunIdentities.insert(identity)
            await inFlightSync.task.value
            return
        }

        // Run, then do one more pass for each generation of duplicates that arrived while
        // we were busy, so the latest state is always observed before we settle. The
        // re-run is cheap when nothing changed: it re-reads the canvas state and stops at
        // the already-synced revision before downloading again.
        repeat {
            pendingRerunIdentities.remove(identity)
            let syncTask = Task { await performSync(identity: identity) }
            inFlightSync = (identity, syncTask)
            await syncTask.value
            if inFlightSync?.identity == identity {
                inFlightSync = nil
            }
        } while pendingRerunIdentities.contains(identity)
    }

    func clearForPrivacy() async {
        await stopInFlightSyncForPrivacy()
        pendingStore.clearAll()
        Self.clearPersistedState(defaults: defaults)
        await localStore.clearForPrivacy()
    }

    func hideForPrivacy() async {
        await stopInFlightSyncForPrivacy()
        Self.clearPersistedState(defaults: defaults)
        await localStore.hideForPrivacy()
    }

    private func stopInFlightSyncForPrivacy() async {
        let runningTask = inFlightSync?.task
        runningTask?.cancel()
        pendingRerunIdentities.removeAll()
        if let runningTask {
            await runningTask.value
        }
        inFlightSync = nil
    }

    nonisolated static func clearPersistedState(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastSyncedKey)
    }

    private func performSync(identity: WidgetSyncIdentity) async {
        guard !Task.isCancelled else {
            return
        }
        #if DEBUG
        logger.debug("Widget canvas sync started.")
        #endif

        // Don't overwrite a local save that hasn't reached the server yet.
        if let pendingSnapshot = pendingStore.pendingSnapshot {
            guard await retryPendingUploadIfNeeded(pendingSnapshot) else {
                return
            }
        } else if pendingStore.hasPending {
            return
        }

        do {
            guard let state = try await gateway.getCanvasState(),
                  let revisionID = state.activeRevisionID,
                  let mediaAssetID = state.payloadMediaAssetID
            else {
                return
            }

            // Skip if we already rendered this revision locally.
            guard revisionID.uuidString != defaults.string(forKey: Self.lastSyncedKey) else {
                return
            }

            // Our own latest revision is already on this device; just mark it seen
            // so we never pull it back over newer local work.
            if let currentUserID = identity.currentUserID,
               state.activeRevisionAuthorUserID == currentUserID {
                defaults.set(revisionID.uuidString, forKey: Self.lastSyncedKey)
                return
            }

            try await applyRemoteRevision(
                state,
                revisionID: revisionID,
                mediaAssetID: mediaAssetID,
                identity: identity
            )
        } catch {
            #if DEBUG
            logger.error("Widget sync failed: \(String(describing: error))")
            #endif
        }
    }

    /// Downloads the partner's revision, persists it (which re-renders previews
    /// and reloads the widget), marks it seen, and tells an open drawing screen
    /// to refresh.
    private func applyRemoteRevision(
        _ state: WidgetCanvasState,
        revisionID: UUID,
        mediaAssetID: UUID,
        identity: WidgetSyncIdentity
    ) async throws {
        guard let url = try await gateway.signedPayloadURL(mediaAssetID: mediaAssetID) else {
            return
        }

        let data = try await downloader.download(from: url)
        try Task.checkCancellation()
        // Required precondition: only show data we can re-render.
        guard (try? PKDrawing(data: data)) != nil else {
            return
        }

        let canvasSide = state.bounds?.canvasSide ?? Double(WidgetDrawingViewModel.fallbackCanvasSide)
        let authorName = Self.authorName(for: state.activeRevisionAuthorUserID, identity: identity)

        // `saveDrawing` persists locally, reloads the widget, and posts
        // `.paeoniaWidgetCanvasDidUpdate` so open in-app surfaces refresh.
        try await localStore.saveDrawing(
            data,
            canvasSize: CGSize(width: canvasSide, height: canvasSide),
            authorName: authorName,
            createdAt: state.revisionCreatedAt ?? Date()
        )

        try Task.checkCancellation()
        defaults.set(revisionID.uuidString, forKey: Self.lastSyncedKey)
    }

    private func retryPendingUploadIfNeeded(_ snapshot: WidgetPendingUploadSnapshot) async -> Bool {
        guard pendingStore.shouldRetry(snapshot) else {
            return false
        }

        guard let drawingData = await localStore.loadSavedDrawing() else {
            pendingStore.clearPending(snapshot.contentHash)
            return true
        }

        guard WidgetCanvasUploadService.sha256Hex(of: drawingData) == snapshot.contentHash,
              (try? PKDrawing(data: drawingData)) != nil
        else {
            pendingStore.clearPending(snapshot.contentHash)
            return true
        }

        guard let pendingUploader else {
            return false
        }

        do {
            try await pendingUploader.uploadPending(snapshot.uploadPayload(with: drawingData))
            return true
        } catch {
            #if DEBUG
            logger.error("Pending widget upload retry failed: \(String(describing: error))")
            #endif
            return false
        }
    }

    nonisolated static func authorName(for authorID: UUID?, identity: WidgetSyncIdentity) -> String? {
        guard let authorID else {
            return nil
        }
        if let currentUserID = identity.currentUserID, authorID == currentUserID {
            return identity.currentDisplayName
        }
        return identity.partnerDisplayName
    }
}

nonisolated struct NoOpWidgetCanvasSync: WidgetCanvasSyncing {
    func sync(identity: WidgetSyncIdentity) {}
    func hideForPrivacy() {}
    func clearForPrivacy() {}
}

nonisolated enum WidgetCanvasSyncServiceFactory {
    static let shared: any WidgetCanvasSyncing = makeLive()

    static func makeDefault() -> any WidgetCanvasSyncing {
        shared
    }

    private static func makeLive() -> any WidgetCanvasSyncing {
        guard let client = try? PaeoniaSupabaseClientProvider.shared.client() else {
            return NoOpWidgetCanvasSync()
        }
        let gateway = LiveSupabaseWidgetCanvasGateway(client: client)
        let pendingStore = WidgetPendingUploadStore.shared
        let uploader = WidgetCanvasUploadService(
            gateway: gateway,
            operationFactory: WidgetCanvasClientOperationFactory.shared,
            pendingStore: pendingStore
        )

        return WidgetCanvasSyncService(
            gateway: gateway,
            localStore: WidgetCanvasService.shared,
            pendingStore: pendingStore,
            pendingUploader: uploader
        )
    }
}
