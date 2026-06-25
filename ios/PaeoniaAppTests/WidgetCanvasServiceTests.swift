import Foundation
import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

struct WidgetCanvasServiceTests {
    @Test func saveWritesCanonicalDrawingPreviewsAndPayload() async throws {
        let environment = TestEnvironment()
        let service = environment.makeService()
        let drawing = makeNonEmptyDrawing()

        try await service.saveDrawing(
            drawing.dataRepresentation(),
            canvasSize: CGSize(width: 300, height: 300),
            authorName: "Hjalmar",
            createdAt: Date()
        )

        // Canonical drawing persisted locally.
        #expect(FileManager.default.fileExists(atPath: environment.canonicalURL.path))

        // Preview images written for both supported families.
        #expect(FileManager.default.fileExists(atPath: environment.previewURL("systemSmall.png").path))
        #expect(FileManager.default.fileExists(atPath: environment.previewURL("systemLarge.png").path))

        // Payload references the rendered previews and carries a content hash.
        let payload = try environment.decodePayload()
        #expect(payload.schemaVersion == WidgetSharePayload.currentSchemaVersion)
        #expect(payload.rendererVersion == WidgetSharePayload.currentRendererVersion)
        #expect(payload.privacyMode == .normal)
        #expect(!payload.isRedacted)
        #expect(payload.contentHash.hasPrefix("sha256-"))
        #expect(payload.authorName == "Hjalmar")
        #expect(payload.previews["systemSmall"] == "Widget/previews/systemSmall.png")
        #expect(payload.previews["systemLarge"] == "Widget/previews/systemLarge.png")

        #expect(environment.reloader.reloadCount == 1)
    }

    @Test func saveRejectsUndecodableData() async {
        let environment = TestEnvironment()
        let service = environment.makeService()

        await #expect(throws: WidgetCanvasError.invalidDrawingData) {
            try await service.saveDrawing(
                Data([0x00, 0x01, 0x02]),
                canvasSize: CGSize(width: 300, height: 300),
                authorName: nil,
                createdAt: Date()
            )
        }

        #expect(!FileManager.default.fileExists(atPath: environment.canonicalURL.path))
        #expect(environment.reloader.reloadCount == 0)
    }

    @Test func loadSavedDrawingReturnsPersistedData() async throws {
        let environment = TestEnvironment()
        let service = environment.makeService()
        let drawing = makeNonEmptyDrawing()

        try await service.saveDrawing(
            drawing.dataRepresentation(),
            canvasSize: CGSize(width: 300, height: 300),
            authorName: nil,
            createdAt: Date()
        )

        let loaded = await service.loadSavedDrawing()

        #expect(loaded == drawing.dataRepresentation())
    }

    @Test func clearForPrivacyRemovesEverythingAndReloads() async throws {
        let environment = TestEnvironment()
        let service = environment.makeService()
        let drawing = makeNonEmptyDrawing()

        try await service.saveDrawing(
            drawing.dataRepresentation(),
            canvasSize: CGSize(width: 300, height: 300),
            authorName: nil,
            createdAt: Date()
        )

        await service.clearForPrivacy()

        #expect(!FileManager.default.fileExists(atPath: environment.canonicalURL.path))
        #expect(!FileManager.default.fileExists(atPath: environment.payloadURL.path))
        #expect(!FileManager.default.fileExists(atPath: environment.previewURL("systemSmall.png").path))
        #expect(await environment.loadedDrawingIsNil(service))
        // One reload for the save, one for the clear.
        #expect(environment.reloader.reloadCount == 2)
    }

    @Test func clearForPrivacyDoesNotReloadWhenNothingStored() async {
        let environment = TestEnvironment()
        let service = environment.makeService()

        await service.clearForPrivacy()

        #expect(environment.reloader.reloadCount == 0)
    }

    @MainActor
    @Test func rasterizerRendersNonEmptyDrawing() throws {
        let pngData = WidgetDrawingRasterizer().renderPNG(
            fromDrawingData: makeNonEmptyDrawing().dataRepresentation(),
            canvasSide: 300,
            pixelWidth: 600
        )

        let rendered = try #require(pngData)
        #expect(!rendered.isEmpty)
    }

    private func makeNonEmptyDrawing() -> PKDrawing {
        let point = PKStrokePoint(
            location: CGPoint(x: 40, y: 40),
            timeOffset: 0,
            size: CGSize(width: 8, height: 8),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: 0
        )
        let secondPoint = PKStrokePoint(
            location: CGPoint(x: 220, y: 220),
            timeOffset: 0.1,
            size: CGSize(width: 8, height: 8),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: 0
        )
        let path = PKStrokePath(controlPoints: [point, secondPoint], creationDate: Date())
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: path)
        return PKDrawing(strokes: [stroke])
    }
}

private final class WidgetReloaderSpy: WidgetTimelineReloading, @unchecked Sendable {
    private(set) var reloadCount = 0

    // `reloadWidget()` is async by protocol; the spy just records a call.
    // swiftlint:disable:next async_without_await
    func reloadWidget() async {
        reloadCount += 1
    }
}

private struct TestEnvironment {
    let containerURL: URL
    let canonicalURL: URL
    let reloader = WidgetReloaderSpy()

    init() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetCanvasServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        containerURL = base.appendingPathComponent("AppGroup", isDirectory: true)
        canonicalURL = base
            .appendingPathComponent("Canonical", isDirectory: true)
            .appendingPathComponent("current.pkdrawing")
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
    }

    func makeService() -> WidgetCanvasService {
        WidgetCanvasService(
            appGroupContainerURL: containerURL,
            canonicalDrawingURL: canonicalURL,
            reloader: reloader
        )
    }

    var payloadURL: URL {
        containerURL.appendingPathComponent("Widget/current.json")
    }

    func previewURL(_ fileName: String) -> URL {
        containerURL.appendingPathComponent("Widget/previews/\(fileName)")
    }

    func decodePayload() throws -> WidgetSharePayload {
        let data = try Data(contentsOf: payloadURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetSharePayload.self, from: data)
    }

    func loadedDrawingIsNil(_ service: WidgetCanvasService) async -> Bool {
        await service.loadSavedDrawing() == nil
    }
}
