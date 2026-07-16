import CryptoKit
import Foundation
import PencilKit
import WidgetKit
#if DEBUG
import OSLog
#endif

extension Notification.Name {
    /// Posted whenever the saved widget drawing/payload changes — a partner's
    /// synced revision or the user's own save — so in-app surfaces can refresh.
    nonisolated static let paeoniaWidgetCanvasDidUpdate = Notification.Name("paeonia.widgetCanvas.didUpdate")
}

/// Reloads the Home Screen widget timeline. Abstracted so the save pipeline can
/// be tested without touching WidgetKit.
nonisolated protocol WidgetTimelineReloading: Sendable {
    func reloadWidget() async
}

nonisolated struct WidgetCenterReloader: WidgetTimelineReloading {
    func reloadWidget() async {
        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: PaeoniaAppGroup.widgetKind)
        }
    }
}

nonisolated enum WidgetCanvasError: Error, Equatable {
    /// The provided data could not be decoded into a `PKDrawing`. This is the
    /// required client-side decode validation; we never persist data we cannot
    /// re-render.
    case invalidDrawingData
    /// The canonical drawing could not be written to local storage.
    case persistenceFailed
}

/// Manages the local-first widget drawing lifecycle: persisting the canonical
/// drawing, rendering widget previews, publishing the App Group payload, and
/// keeping private content off the Home Screen when a session ends.
///
/// Remote sync (uploading the canonical `.pkdrawing` payload and propagating a
/// partner's revision) is a separate concern handled by the sync layer once it
/// exists; this service owns only the on-device surface.
/// The last saved drawing plus its on-canvas attribution: who saved it and when.
/// `authorName`/`createdAt` are nil when no matching saved metadata is available.
nonisolated struct WidgetCanvasSnapshot: Sendable, Equatable {
    let drawingData: Data
    let authorName: String?
    let createdAt: Date?
}

nonisolated protocol WidgetCanvasManaging: Sendable {
    /// Returns the canonical data for the last saved drawing, if one exists and
    /// still decodes.
    func loadSavedDrawing() async -> Data?

    /// Returns the last saved drawing together with its attribution (author name
    /// and save time) for display on the canvas. Defaults to the canonical
    /// drawing with no attribution; `WidgetCanvasService` fills in the metadata.
    func loadSavedSnapshot() async -> WidgetCanvasSnapshot?

    /// Persists the drawing locally, renders widget previews, updates the App
    /// Group payload, and reloads the widget. `authorName` is the display name
    /// of whoever saved the drawing, and `createdAt` is when it was drawn (the
    /// author's save time for synced revisions), both shown on the widget.
    func saveDrawing(
        _ drawingData: Data,
        canvasSize: CGSize,
        authorName: String?,
        createdAt: Date
    ) async throws

    /// Removes the saved drawing and widget previews so private content does not
    /// linger on the Home Screen after a session ends.
    func clearForPrivacy() async

    /// Hides widget-visible derivatives while preserving the canonical drawing
    /// for a temporary entitlement loss.
    func hideForPrivacy() async
}

extension WidgetCanvasManaging {
    func loadSavedSnapshot() async -> WidgetCanvasSnapshot? {
        guard let data = await loadSavedDrawing() else {
            return nil
        }
        return WidgetCanvasSnapshot(drawingData: data, authorName: nil, createdAt: nil)
    }

    func hideForPrivacy() async {
        await clearForPrivacy()
    }
}

actor WidgetCanvasService: WidgetCanvasManaging {
    nonisolated static let shared = WidgetCanvasService()

    private nonisolated struct PreviewSpec {
        let family: String
        let fileStem: String
        let pixelWidth: CGFloat

        func fileName(revisionID: String) -> String {
            "\(fileStem)-\(revisionID).png"
        }
    }

    private nonisolated static let previewSpecs: [PreviewSpec] = [
        PreviewSpec(family: "systemSmall", fileStem: "systemSmall", pixelWidth: 480),
        PreviewSpec(family: "systemLarge", fileStem: "systemLarge", pixelWidth: 880),
    ]
    /// `reloadTimelines` only requests a reload; it does not tell us when every
    /// previously rendered timeline entry has stopped using its preview URL.
    /// Keep unreferenced revisions for a full day so a still-live entry never
    /// points at a file removed immediately after a save.
    private nonisolated static let unreferencedPreviewRetention: TimeInterval = 24 * 60 * 60

    private let appGroupContainerURL: URL?
    private let canonicalDrawingURL: URL?
    private let rasterizer: any WidgetDrawingRasterizing
    private let reloader: any WidgetTimelineReloading
    private var privacyGeneration: UInt64 = 0
    private var publicationGeneration: UInt64 = 0

    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Widget"
    )
    #endif

    init(
        appGroupContainerURL: URL? = PaeoniaAppGroup.containerURL,
        canonicalDrawingURL: URL? = WidgetCanvasService.defaultCanonicalDrawingURL(),
        rasterizer: any WidgetDrawingRasterizing = WidgetDrawingRasterizer(),
        reloader: any WidgetTimelineReloading = WidgetCenterReloader()
    ) {
        self.appGroupContainerURL = appGroupContainerURL
        self.canonicalDrawingURL = canonicalDrawingURL
        self.rasterizer = rasterizer
        self.reloader = reloader
    }

    // Synchronous, but actor isolation makes it `await` from outside, so it
    // still satisfies the protocol's `async` requirement.
    func loadSavedDrawing() -> Data? {
        guard let canonicalDrawingURL,
              let data = try? Data(contentsOf: canonicalDrawingURL),
              (try? PKDrawing(data: data)) != nil
        else {
            return nil
        }

        return data
    }

    func loadSavedSnapshot() -> WidgetCanvasSnapshot? {
        guard let data = loadSavedDrawing() else {
            return nil
        }
        // Attribution lives in the published widget payload. Only trust it when
        // it describes this exact drawing, so we never label a drawing with a
        // different revision's author or time.
        let metadata = savedPayloadMetadata(matching: data)
        return WidgetCanvasSnapshot(
            drawingData: data,
            authorName: metadata?.authorName,
            createdAt: metadata?.createdAt
        )
    }

    /// Reads the saved widget payload and returns its attribution only if its
    /// content hash matches `data`.
    private func savedPayloadMetadata(matching data: Data) -> (authorName: String?, createdAt: Date)? {
        guard let appGroupContainerURL else {
            return nil
        }
        let payloadURL = appGroupContainerURL.appendingPathComponent(PaeoniaAppGroup.widgetPayloadPath)
        guard let payloadData = try? Data(contentsOf: payloadURL),
              let payload = try? WidgetSharePayload.decoder().decode(WidgetSharePayload.self, from: payloadData),
              payload.contentHash == Self.contentHash(for: data)
        else {
            return nil
        }
        return (payload.authorName, payload.createdAt)
    }

    func saveDrawing(
        _ drawingData: Data,
        canvasSize: CGSize,
        authorName: String?,
        createdAt: Date
    ) async throws {
        // Required precondition: never persist data we cannot re-render.
        guard (try? PKDrawing(data: drawingData)) != nil else {
            throw WidgetCanvasError.invalidDrawingData
        }

        publicationGeneration &+= 1
        let expectedPublicationGeneration = publicationGeneration
        let expectedPrivacyGeneration = privacyGeneration
        let stagedCanonicalDrawingURL = try stageCanonicalDrawing(drawingData)
        defer {
            try? FileManager.default.removeItem(at: stagedCanonicalDrawingURL)
        }

        // Keep the prior canonical drawing live until every derived widget file
        // has published successfully. Otherwise a failed save can reappear after
        // relaunch even though the UI correctly reported that it did not finish.
        do {
            try await publishWidgetPayload(
                drawingData: drawingData,
                canvasSize: canvasSize,
                authorName: authorName,
                createdAt: createdAt,
                privacyGeneration: expectedPrivacyGeneration,
                publicationGeneration: expectedPublicationGeneration
            )
            try checkGenerations(
                privacy: expectedPrivacyGeneration,
                publication: expectedPublicationGeneration
            )
            try commitCanonicalDrawing(from: stagedCanonicalDrawingURL)
        } catch {
            #if DEBUG
            logger.error("Failed to publish widget payload: \(String(describing: error))")
            #endif
            throw error
        }

        // One signal for any payload write — a partner's synced revision or the
        // user's own save — so in-app surfaces (home preview, drawing canvas)
        // refresh without waiting to reappear. Posted on the main thread because
        // this runs on the service actor (a background thread): `.onReceive`
        // subscribers update `@Observable` view state synchronously on the
        // posting thread, and doing that off-main crashes SwiftUI.
        await MainActor.run {
            NotificationCenter.default.post(name: .paeoniaWidgetCanvasDidUpdate, object: nil)
        }
    }

    func clearForPrivacy() async {
        privacyGeneration &+= 1
        let fileManager = FileManager.default
        var didRemoveSomething = false

        if let canonicalDrawingURL, fileManager.fileExists(atPath: canonicalDrawingURL.path) {
            try? fileManager.removeItem(at: canonicalDrawingURL)
            didRemoveSomething = true
        }

        didRemoveSomething = removeWidgetVisibleFiles(fileManager: fileManager) || didRemoveSomething

        await reloadWidgetIfNeeded(didRemoveSomething)
    }

    func hideForPrivacy() async {
        privacyGeneration &+= 1
        let didRemoveSomething = removeWidgetVisibleFiles(fileManager: .default)
        await reloadWidgetIfNeeded(didRemoveSomething)
    }

    private func removeWidgetVisibleFiles(fileManager: FileManager) -> Bool {
        guard let appGroupContainerURL else {
            return false
        }

        var didRemoveSomething = false
        let payloadURL = appGroupContainerURL.appendingPathComponent(PaeoniaAppGroup.widgetPayloadPath)
        if fileManager.fileExists(atPath: payloadURL.path) {
            try? fileManager.removeItem(at: payloadURL)
            didRemoveSomething = true
        }

        let previewsURL = appGroupContainerURL.appendingPathComponent(
            PaeoniaAppGroup.widgetPreviewsDirectory,
            isDirectory: true
        )
        if fileManager.fileExists(atPath: previewsURL.path) {
            try? fileManager.removeItem(at: previewsURL)
            didRemoveSomething = true
        }

        return didRemoveSomething
    }

    private func reloadWidgetIfNeeded(_ didRemoveSomething: Bool) async {
        // Only reload when something actually changed so leaving the paired
        // state with an already-empty widget does not churn the timeline.
        if didRemoveSomething {
            await reloader.reloadWidget()
        }
    }

    private func stageCanonicalDrawing(_ data: Data) throws -> URL {
        guard let canonicalDrawingURL else {
            throw WidgetCanvasError.persistenceFailed
        }

        let directoryURL = canonicalDrawingURL.deletingLastPathComponent()
        let stagedURL = directoryURL.appendingPathComponent(
            ".\(canonicalDrawingURL.lastPathComponent).\(UUID().uuidString).staged"
        )

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(to: stagedURL, options: .atomic)
            return stagedURL
        } catch {
            throw WidgetCanvasError.persistenceFailed
        }
    }

    private func commitCanonicalDrawing(from stagedURL: URL) throws {
        guard let canonicalDrawingURL else {
            throw WidgetCanvasError.persistenceFailed
        }

        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: canonicalDrawingURL.path) {
                _ = try fileManager.replaceItemAt(canonicalDrawingURL, withItemAt: stagedURL)
            } else {
                try fileManager.moveItem(at: stagedURL, to: canonicalDrawingURL)
            }
        } catch {
            throw WidgetCanvasError.persistenceFailed
        }
    }

    private func publishWidgetPayload(
        drawingData: Data,
        canvasSize: CGSize,
        authorName: String?,
        createdAt: Date,
        privacyGeneration expectedPrivacyGeneration: UInt64,
        publicationGeneration expectedPublicationGeneration: UInt64
    ) async throws {
        try checkGenerations(
            privacy: expectedPrivacyGeneration,
            publication: expectedPublicationGeneration
        )
        guard let appGroupContainerURL else {
            return
        }

        let fileManager = FileManager.default
        let previewsURL = appGroupContainerURL.appendingPathComponent(
            PaeoniaAppGroup.widgetPreviewsDirectory,
            isDirectory: true
        )
        try fileManager.createDirectory(at: previewsURL, withIntermediateDirectories: true)

        let revisionID = UUID().uuidString.lowercased()
        var previews: [String: String] = [:]
        var newPreviewURLs: [URL] = []
        var didPublishPayload = false
        // Until the metadata swap succeeds, every new revision file is an
        // unreferenced staging artifact. Clean those up on any render/write/
        // privacy-generation failure without touching the prior live payload.
        defer {
            if !didPublishPayload {
                newPreviewURLs.forEach { try? fileManager.removeItem(at: $0) }
            }
        }

        for spec in Self.previewSpecs {
            guard let pngData = await rasterizer.renderPNG(
                fromDrawingData: drawingData,
                canvasSide: canvasSize.width,
                pixelWidth: spec.pixelWidth
            ) else {
                // Both declared Home Screen families are supported. Publishing
                // a partial payload would make one of them silently regress to
                // the placeholder while Save reports success.
                throw WidgetCanvasError.persistenceFailed
            }
            try checkGenerations(
                privacy: expectedPrivacyGeneration,
                publication: expectedPublicationGeneration
            )

            let fileName = spec.fileName(revisionID: revisionID)
            let previewURL = previewsURL.appendingPathComponent(fileName)
            try pngData.write(to: previewURL, options: .atomic)
            newPreviewURLs.append(previewURL)
            previews[spec.family] = "\(PaeoniaAppGroup.widgetPreviewsDirectory)/\(fileName)"
        }

        guard previews.count == Self.previewSpecs.count else {
            throw WidgetCanvasError.persistenceFailed
        }

        let trimmedAuthorName = authorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = WidgetSharePayload(
            revisionID: revisionID,
            authorName: trimmedAuthorName?.isEmpty == false ? trimmedAuthorName : nil,
            createdAt: createdAt,
            renderedAt: Date(),
            privacyMode: .normal,
            isRedacted: false,
            contentHash: Self.contentHash(for: drawingData),
            previews: previews
        )

        // Write the metadata last so it never references previews that do not
        // exist yet; the widget falls back to a placeholder otherwise.
        let payloadData = try WidgetSharePayload.encoder().encode(payload)
        let payloadURL = appGroupContainerURL.appendingPathComponent(PaeoniaAppGroup.widgetPayloadPath)
        try checkGenerations(
            privacy: expectedPrivacyGeneration,
            publication: expectedPublicationGeneration
        )
        try payloadData.write(to: payloadURL, options: .atomic)
        didPublishPayload = true

        await reloader.reloadWidget()
        try checkGenerations(
            privacy: expectedPrivacyGeneration,
            publication: expectedPublicationGeneration
        )
        removeExpiredUnreferencedPreviews(
            keeping: Set(previews.values),
            previewsURL: previewsURL,
            fileManager: fileManager
        )
    }

    /// Preview names include the revision so a new timeline never points at the
    /// same URL as stale image bytes. Cleanup starts only after the new payload
    /// is atomically visible and retains recent revisions for old timeline
    /// entries; a crash can leave an orphan but cannot break the current payload.
    private func removeExpiredUnreferencedPreviews(
        keeping referencedPaths: Set<String>,
        previewsURL: URL,
        fileManager: FileManager
    ) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: previewsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let expirationDate = Date().addingTimeInterval(-Self.unreferencedPreviewRetention)
        for fileURL in files {
            let relativePath = "\(PaeoniaAppGroup.widgetPreviewsDirectory)/\(fileURL.lastPathComponent)"
            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey]
            )
            guard !referencedPaths.contains(relativePath),
                  values?.isRegularFile == true,
                  let modifiedAt = values?.contentModificationDate,
                  modifiedAt <= expirationDate
            else {
                continue
            }
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func checkGenerations(privacy: UInt64, publication: UInt64) throws {
        guard privacy == privacyGeneration,
              publication == publicationGeneration
        else {
            throw CancellationError()
        }
    }

    nonisolated static func contentHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return "sha256-" + digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func defaultCanonicalDrawingURL() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }

        return base
            .appendingPathComponent("WidgetCanvas", isDirectory: true)
            .appendingPathComponent("current.pkdrawing")
    }
}
