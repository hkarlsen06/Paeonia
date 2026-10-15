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
actor WidgetCanvasService: WidgetCanvasManaging {
    nonisolated static let shared = WidgetCanvasService()

    let appGroupContainerURL: URL?
    private let canonicalDrawingURL: URL?
    let rasterizer: any WidgetDrawingRasterizing
    let reloader: any WidgetTimelineReloading
    /// App Group defaults shared with the widget extension. The widget reads
    /// `widgetPrivacyEpochKey` before and during a refresh and gives up if a
    /// purge bumped it meanwhile.
    private let sharedDefaults: UserDefaults?
    nonisolated static let widgetPrivacyEpochKey = "paeonia.widget.privacyEpoch"
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
        reloader: any WidgetTimelineReloading = WidgetCenterReloader(),
        sharedDefaults: UserDefaults? = UserDefaults(suiteName: PaeoniaAppGroup.identifier)
    ) {
        self.appGroupContainerURL = appGroupContainerURL
        self.canonicalDrawingURL = canonicalDrawingURL
        self.rasterizer = rasterizer
        self.reloader = reloader
        self.sharedDefaults = sharedDefaults
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
            createdAt: metadata?.createdAt,
            canvasSide: metadata.map { CGFloat($0.canvasSide) }
        )
    }

    /// Reads the saved widget payload, but only if its content hash matches
    /// `data`, so its attribution describes this exact drawing.
    private func savedPayloadMetadata(matching data: Data) -> WidgetSharePayload? {
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
        return payload
    }

    func saveDrawing(
        _ drawingData: Data,
        canvasSize: CGSize,
        authorName: String?,
        createdAt: Date
    ) async throws {
        try await publish(
            WidgetCanvasPublication(
                drawingData: drawingData,
                canvasSize: canvasSize,
                authorName: authorName,
                createdAt: createdAt,
                serverRevisionID: nil
            )
        )
    }

    func saveSyncedDrawing(
        _ drawingData: Data,
        canvasSize: CGSize,
        authorName: String?,
        createdAt: Date,
        revisionID: UUID
    ) async throws {
        try await publish(
            WidgetCanvasPublication(
                drawingData: drawingData,
                canvasSize: canvasSize,
                authorName: authorName,
                createdAt: createdAt,
                serverRevisionID: revisionID.uuidString.lowercased()
            )
        )
    }

    private func publish(_ publication: WidgetCanvasPublication) async throws {
        // Required precondition: never persist data we cannot re-render.
        guard (try? PKDrawing(data: publication.drawingData)) != nil else {
            throw WidgetCanvasError.invalidDrawingData
        }

        publicationGeneration &+= 1
        let generations = WidgetCanvasGenerations(privacy: privacyGeneration, publication: publicationGeneration)
        let stagedCanonicalDrawingURL = try stageCanonicalDrawing(publication.drawingData)
        defer {
            try? FileManager.default.removeItem(at: stagedCanonicalDrawingURL)
        }

        // Keep the prior canonical drawing live until every derived widget file
        // has published successfully. Otherwise a failed save can reappear after
        // relaunch even though the UI correctly reported that it did not finish.
        do {
            try await publishWidgetPayload(publication, generations: generations)
            try checkGenerations(generations)
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
        bumpWidgetPrivacyEpoch()
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
        bumpWidgetPrivacyEpoch()
        let didRemoveSomething = removeWidgetVisibleFiles(fileManager: .default)
        await reloadWidgetIfNeeded(didRemoveSomething)
    }

    /// Checks what the home card needs, not only that the file exists: an older
    /// widget extension wrote a payload this app could not read.
    func isShowingSavedDrawing() -> Bool {
        guard let appGroupContainerURL,
              let payloadData = try? Data(
                contentsOf: appGroupContainerURL.appendingPathComponent(PaeoniaAppGroup.widgetPayloadPath)
              ),
              let payload = try? WidgetSharePayload.decoder().decode(WidgetSharePayload.self, from: payloadData)
        else {
            return false
        }
        return payload.previews.values.allSatisfy { path in
            FileManager.default.fileExists(atPath: appGroupContainerURL.appendingPathComponent(path).path)
        }
    }

    /// Tells a widget refresh that is running in the extension right now that it
    /// must not publish what it downloaded. Bumped before the files go.
    private func bumpWidgetPrivacyEpoch() {
        guard let sharedDefaults else {
            return
        }
        let nextEpoch = sharedDefaults.integer(forKey: Self.widgetPrivacyEpochKey) &+ 1
        sharedDefaults.set(nextEpoch, forKey: Self.widgetPrivacyEpochKey)
    }

    private func removeWidgetVisibleFiles(fileManager: FileManager) -> Bool {
        guard let appGroupContainerURL else {
            return false
        }
        return WidgetPreviewFiles.removeWidgetVisibleFiles(in: appGroupContainerURL, fileManager: fileManager)
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

    func checkGenerations(_ expected: WidgetCanvasGenerations) throws {
        guard expected.privacy == privacyGeneration,
              expected.publication == publicationGeneration
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
