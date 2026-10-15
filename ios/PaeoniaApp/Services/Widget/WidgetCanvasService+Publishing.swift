import Foundation

/// A drawing on its way to the Home Screen widget.
nonisolated struct WidgetCanvasPublication {
    let drawingData: Data
    let canvasSize: CGSize
    let authorName: String?
    let createdAt: Date
    let serverRevisionID: String?
}

/// The privacy and publication counters when a publication started. A newer
/// publication or a privacy purge moves them on, which cancels the older one.
nonisolated struct WidgetCanvasGenerations {
    let privacy: UInt64
    let publication: UInt64
}

extension WidgetCanvasService {
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

    func publishWidgetPayload(
        _ publication: WidgetCanvasPublication,
        generations: WidgetCanvasGenerations
    ) async throws {
        try checkGenerations(generations)
        guard let appGroupContainerURL else {
            return
        }

        let fileManager = FileManager.default
        let previewsURL = appGroupContainerURL.appendingPathComponent(
            PaeoniaAppGroup.widgetPreviewsDirectory,
            isDirectory: true
        )
        try fileManager.createDirectory(at: previewsURL, withIntermediateDirectories: true)

        // File names always get a fresh id, so this never overwrites (or, on a
        // failed write, deletes) a file the widget extension wrote for the same
        // server revision.
        let fileRevisionID = UUID().uuidString.lowercased()
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

        let previews = try await renderPreviews(
            publication,
            fileRevisionID: fileRevisionID,
            previewsURL: previewsURL,
            generations: generations,
            writtenURLs: &newPreviewURLs
        )

        // Write the metadata last so it never references previews that do not
        // exist yet; the widget falls back to a placeholder otherwise.
        let payload = Self.makePayload(publication, fileRevisionID: fileRevisionID, previews: previews)
        let payloadData = try WidgetSharePayload.encoder().encode(payload)
        let payloadURL = appGroupContainerURL.appendingPathComponent(PaeoniaAppGroup.widgetPayloadPath)
        try checkGenerations(generations)
        try payloadData.write(to: payloadURL, options: .atomic)
        didPublishPayload = true

        await reloader.reloadWidget()
        try checkGenerations(generations)
        WidgetPreviewFiles.removeExpiredUnreferencedPreviews(
            keeping: Set(previews.values),
            previewsURL: previewsURL,
            olderThan: Date().addingTimeInterval(-Self.unreferencedPreviewRetention),
            fileManager: fileManager
        )
    }

    /// Renders and writes one preview per Home Screen family. Returns the paths
    /// by family, and adds every file it wrote to `writtenURLs` so the caller can
    /// remove them when the publication fails later.
    private func renderPreviews(
        _ publication: WidgetCanvasPublication,
        fileRevisionID: String,
        previewsURL: URL,
        generations: WidgetCanvasGenerations,
        writtenURLs: inout [URL]
    ) async throws -> [String: String] {
        var previews: [String: String] = [:]
        for spec in Self.previewSpecs {
            guard let pngData = await rasterizer.renderPNG(
                fromDrawingData: publication.drawingData,
                canvasSide: publication.canvasSize.width,
                pixelWidth: spec.pixelWidth
            ) else {
                // Both declared Home Screen families are supported. Publishing
                // a partial payload would make one of them silently regress to
                // the placeholder while Save reports success.
                throw WidgetCanvasError.persistenceFailed
            }
            try checkGenerations(generations)

            let fileName = spec.fileName(revisionID: fileRevisionID)
            let previewURL = previewsURL.appendingPathComponent(fileName)
            try pngData.write(to: previewURL, options: .atomic)
            writtenURLs.append(previewURL)
            previews[spec.family] = "\(PaeoniaAppGroup.widgetPreviewsDirectory)/\(fileName)"
        }

        guard previews.count == Self.previewSpecs.count else {
            throw WidgetCanvasError.persistenceFailed
        }
        return previews
    }

    private nonisolated static func makePayload(
        _ publication: WidgetCanvasPublication,
        fileRevisionID: String,
        previews: [String: String]
    ) -> WidgetSharePayload {
        let trimmedAuthorName = publication.authorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return WidgetSharePayload(
            revisionID: publication.serverRevisionID ?? fileRevisionID,
            authorName: trimmedAuthorName?.isEmpty == false ? trimmedAuthorName : nil,
            createdAt: publication.createdAt,
            renderedAt: Date(),
            privacyMode: .normal,
            isRedacted: false,
            contentHash: contentHash(for: publication.drawingData),
            previews: previews,
            canvasSide: Double(publication.canvasSize.width)
        )
    }
}
