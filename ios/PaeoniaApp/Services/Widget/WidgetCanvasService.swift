import CryptoKit
import Foundation
import PencilKit
import WidgetKit
#if DEBUG
import OSLog
#endif

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
nonisolated protocol WidgetCanvasManaging: Sendable {
    /// Returns the canonical data for the last saved drawing, if one exists and
    /// still decodes.
    func loadSavedDrawing() async -> Data?

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
}

actor WidgetCanvasService: WidgetCanvasManaging {
    nonisolated static let shared = WidgetCanvasService()

    private nonisolated struct PreviewSpec {
        let family: String
        let fileName: String
        let pixelWidth: CGFloat
    }

    private nonisolated static let previewSpecs: [PreviewSpec] = [
        PreviewSpec(family: "systemSmall", fileName: "systemSmall.png", pixelWidth: 480),
        PreviewSpec(family: "systemLarge", fileName: "systemLarge.png", pixelWidth: 880),
    ]

    private let appGroupContainerURL: URL?
    private let canonicalDrawingURL: URL?
    private let rasterizer: WidgetDrawingRasterizer
    private let reloader: any WidgetTimelineReloading

    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Widget"
    )
    #endif

    init(
        appGroupContainerURL: URL? = PaeoniaAppGroup.containerURL,
        canonicalDrawingURL: URL? = WidgetCanvasService.defaultCanonicalDrawingURL(),
        rasterizer: WidgetDrawingRasterizer = WidgetDrawingRasterizer(),
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

        try persistCanonicalDrawing(drawingData)

        // The widget payload is derived cache. A failure here must not lose the
        // user's saved drawing, which already succeeded above.
        do {
            try await publishWidgetPayload(
                drawingData: drawingData,
                canvasSize: canvasSize,
                authorName: authorName,
                createdAt: createdAt
            )
        } catch {
            #if DEBUG
            logger.error("Failed to publish widget payload: \(String(describing: error))")
            #endif
        }
    }

    func clearForPrivacy() async {
        let fileManager = FileManager.default
        var didRemoveSomething = false

        if let canonicalDrawingURL, fileManager.fileExists(atPath: canonicalDrawingURL.path) {
            try? fileManager.removeItem(at: canonicalDrawingURL)
            didRemoveSomething = true
        }

        if let appGroupContainerURL {
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
        }

        // Only reload when something actually changed so leaving the paired
        // state with an already-empty widget does not churn the timeline.
        if didRemoveSomething {
            await reloader.reloadWidget()
        }
    }

    private func persistCanonicalDrawing(_ data: Data) throws {
        guard let canonicalDrawingURL else {
            throw WidgetCanvasError.persistenceFailed
        }

        do {
            try FileManager.default.createDirectory(
                at: canonicalDrawingURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: canonicalDrawingURL, options: .atomic)
        } catch {
            throw WidgetCanvasError.persistenceFailed
        }
    }

    private func publishWidgetPayload(
        drawingData: Data,
        canvasSize: CGSize,
        authorName: String?,
        createdAt: Date
    ) async throws {
        guard let appGroupContainerURL else {
            return
        }

        let fileManager = FileManager.default
        let previewsURL = appGroupContainerURL.appendingPathComponent(
            PaeoniaAppGroup.widgetPreviewsDirectory,
            isDirectory: true
        )
        try fileManager.createDirectory(at: previewsURL, withIntermediateDirectories: true)

        var previews: [String: String] = [:]
        for spec in Self.previewSpecs {
            guard let pngData = await rasterizer.renderPNG(
                fromDrawingData: drawingData,
                canvasSide: canvasSize.width,
                pixelWidth: spec.pixelWidth
            ) else {
                continue
            }

            try pngData.write(to: previewsURL.appendingPathComponent(spec.fileName), options: .atomic)
            previews[spec.family] = "\(PaeoniaAppGroup.widgetPreviewsDirectory)/\(spec.fileName)"
        }

        guard !previews.isEmpty else {
            throw WidgetCanvasError.persistenceFailed
        }

        let trimmedAuthorName = authorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = WidgetSharePayload(
            revisionID: UUID().uuidString,
            authorName: trimmedAuthorName?.isEmpty == false ? trimmedAuthorName : nil,
            createdAt: createdAt,
            renderedAt: Date(),
            contentHash: Self.contentHash(for: drawingData),
            previews: previews
        )

        // Write the metadata last so it never references previews that do not
        // exist yet; the widget falls back to a placeholder otherwise.
        let payloadData = try WidgetSharePayload.encoder().encode(payload)
        let payloadURL = appGroupContainerURL.appendingPathComponent(PaeoniaAppGroup.widgetPayloadPath)
        try payloadData.write(to: payloadURL, options: .atomic)

        await reloader.reloadWidget()
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
