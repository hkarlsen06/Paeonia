import Foundation
import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

struct WidgetCanvasServiceTests {
    @Test func sharePayloadDefaultsToRedacted() {
        let payload = WidgetSharePayload(
            revisionID: UUID().uuidString,
            authorName: nil,
            createdAt: .now,
            renderedAt: .now,
            contentHash: "sha256-test",
            previews: ["systemSmall": "Widget/previews/systemSmall.png"]
        )

        #expect(payload.privacyMode == .redacted)
        #expect(payload.isRedacted)
    }

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

        // Payload references the rendered previews and carries a content hash.
        let payload = try environment.decodePayload()
        #expect(payload.schemaVersion == WidgetSharePayload.currentSchemaVersion)
        #expect(payload.rendererVersion == WidgetSharePayload.currentRendererVersion)
        #expect(payload.privacyMode == .normal)
        #expect(!payload.isRedacted)
        #expect(payload.contentHash.hasPrefix("sha256-"))
        #expect(payload.authorName == "Hjalmar")
        let smallPreviewPath = try #require(payload.previews["systemSmall"])
        let largePreviewPath = try #require(payload.previews["systemLarge"])
        #expect(smallPreviewPath.hasPrefix("Widget/previews/systemSmall-"))
        #expect(largePreviewPath.hasPrefix("Widget/previews/systemLarge-"))
        #expect(FileManager.default.fileExists(atPath: environment.url(relativePath: smallPreviewPath).path))
        #expect(FileManager.default.fileExists(atPath: environment.url(relativePath: largePreviewPath).path))

        #expect(environment.reloader.reloadCount == 1)
    }

    @Test func secondSavePublishesNewURLsAndRetainsPriorTimelineFiles() async throws {
        let environment = TestEnvironment()
        let service = environment.makeService()

        try await service.saveDrawing(
            makeNonEmptyDrawing().dataRepresentation(),
            canvasSize: CGSize(width: 300, height: 300),
            authorName: "Hjalmar",
            createdAt: Date()
        )
        let firstPayload = try environment.decodePayload()
        let firstPaths = Set(firstPayload.previews.values)

        try await service.saveDrawing(
            makeNonEmptyDrawing(offset: 18).dataRepresentation(),
            canvasSize: CGSize(width: 300, height: 300),
            authorName: "Partner",
            createdAt: Date()
        )
        let secondPayload = try environment.decodePayload()
        let secondPaths = Set(secondPayload.previews.values)

        #expect(firstPaths.isDisjoint(with: secondPaths))
        #expect(secondPaths.allSatisfy {
            FileManager.default.fileExists(atPath: environment.url(relativePath: $0).path)
        })
        #expect(firstPaths.allSatisfy {
            FileManager.default.fileExists(atPath: environment.url(relativePath: $0).path)
        })
        #expect(environment.previewFiles.count == 4)
        #expect(environment.reloader.reloadCount == 2)
    }

    @Test func laterSaveCleansExpiredUnreferencedTimelineFiles() async throws {
        let environment = TestEnvironment()
        let service = environment.makeService()

        try await service.saveDrawing(
            makeNonEmptyDrawing().dataRepresentation(),
            canvasSize: CGSize(width: 300, height: 300),
            authorName: "Hjalmar",
            createdAt: Date()
        )
        let firstPayload = try environment.decodePayload()
        let firstPaths = Set(firstPayload.previews.values)
        let expiredModificationDate = Date().addingTimeInterval(-25 * 60 * 60)
        for path in firstPaths {
            try FileManager.default.setAttributes(
                [.modificationDate: expiredModificationDate],
                ofItemAtPath: environment.url(relativePath: path).path
            )
        }

        try await service.saveDrawing(
            makeNonEmptyDrawing(offset: 18).dataRepresentation(),
            canvasSize: CGSize(width: 300, height: 300),
            authorName: "Partner",
            createdAt: Date()
        )
        let secondPaths = Set(try environment.decodePayload().previews.values)

        #expect(firstPaths.allSatisfy {
            !FileManager.default.fileExists(atPath: environment.url(relativePath: $0).path)
        })
        #expect(secondPaths.allSatisfy {
            FileManager.default.fileExists(atPath: environment.url(relativePath: $0).path)
        })
        #expect(environment.previewFiles.count == 2)
    }

    @Test func partialPreviewFailurePreservesPriorPayloadAndCleansStagedFiles() async throws {
        let environment = TestEnvironment()
        let liveService = environment.makeService()
        try await liveService.saveDrawing(
            makeNonEmptyDrawing().dataRepresentation(),
            canvasSize: CGSize(width: 300, height: 300),
            authorName: "Hjalmar",
            createdAt: Date()
        )
        let priorPayload = try environment.decodePayload()
        let priorPaths = Set(priorPayload.previews.values)
        let priorCanonicalDrawing = try Data(contentsOf: environment.canonicalURL)

        let partialService = environment.makeService(rasterizer: PartialWidgetRasterizer())
        await #expect(throws: WidgetCanvasError.persistenceFailed) {
            try await partialService.saveDrawing(
                makeNonEmptyDrawing(offset: 24).dataRepresentation(),
                canvasSize: CGSize(width: 300, height: 300),
                authorName: "Partner",
                createdAt: Date()
            )
        }

        #expect(try environment.decodePayload() == priorPayload)
        #expect(try Data(contentsOf: environment.canonicalURL) == priorCanonicalDrawing)
        #expect(priorPaths.allSatisfy {
            FileManager.default.fileExists(atPath: environment.url(relativePath: $0).path)
        })
        let priorFileNames = Set(priorPaths.map { URL(fileURLWithPath: $0).lastPathComponent })
        #expect(Set(environment.previewFiles.map(\.lastPathComponent)) == priorFileNames)
        #expect(environment.reloader.reloadCount == 1)
    }

    @MainActor
    @Test func overlappingSavePublishesOnlyLatestStartedDrawing() async throws {
        let environment = TestEnvironment()
        let rasterizer = SuspendingFirstWidgetRasterizer()
        let service = environment.makeService(rasterizer: rasterizer)
        let firstData = makeNonEmptyDrawing().dataRepresentation()
        let latestData = makeNonEmptyDrawing(offset: 32).dataRepresentation()

        let firstSave = Task { @MainActor in
            do {
                try await service.saveDrawing(
                    firstData,
                    canvasSize: CGSize(width: 300, height: 300),
                    authorName: "First",
                    createdAt: Date(timeIntervalSinceReferenceDate: 1)
                )
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        await rasterizer.waitUntilFirstRenderStarts()

        try await service.saveDrawing(
            latestData,
            canvasSize: CGSize(width: 300, height: 300),
            authorName: "Latest",
            createdAt: Date(timeIntervalSinceReferenceDate: 2)
        )
        rasterizer.resumeFirstRender()

        #expect(await firstSave.value)
        let payload = try environment.decodePayload()
        #expect(payload.authorName == "Latest")
        #expect(payload.contentHash == WidgetCanvasService.contentHash(for: latestData))
        #expect(await service.loadSavedDrawing() == latestData)
        #expect(environment.reloader.reloadCount == 1)
        #expect(environment.previewFiles.count == 2)
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
        #expect(environment.previewFiles.isEmpty)
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

    @Test func temporaryPrivacyHidePreservesCanonicalDrawingButRemovesWidgetCopies() async throws {
        let environment = TestEnvironment()
        let service = environment.makeService()
        let drawing = makeNonEmptyDrawing()

        try await service.saveDrawing(
            drawing.dataRepresentation(),
            canvasSize: CGSize(width: 300, height: 300),
            authorName: nil,
            createdAt: Date()
        )

        await service.hideForPrivacy()

        #expect(FileManager.default.fileExists(atPath: environment.canonicalURL.path))
        #expect(!FileManager.default.fileExists(atPath: environment.payloadURL.path))
        #expect(environment.previewFiles.isEmpty)
        #expect(await service.loadSavedDrawing() == drawing.dataRepresentation())
        #expect(environment.reloader.reloadCount == 2)
    }

    @MainActor
    @Test func rasterizerRendersNonEmptyDrawing() async throws {
        let pngData = await WidgetDrawingRasterizer().renderPNG(
            fromDrawingData: makeNonEmptyDrawing().dataRepresentation(),
            canvasSide: 300,
            pixelWidth: 600
        )

        let rendered = try #require(pngData)
        #expect(!rendered.isEmpty)
    }

    private func makeNonEmptyDrawing(offset: CGFloat = 0) -> PKDrawing {
        let point = PKStrokePoint(
            location: CGPoint(x: 40 + offset, y: 40 + offset),
            timeOffset: 0,
            size: CGSize(width: 8, height: 8),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: 0
        )
        let secondPoint = PKStrokePoint(
            location: CGPoint(x: 220 + offset, y: 220 + offset),
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

    func makeService(
        rasterizer: any WidgetDrawingRasterizing = WidgetDrawingRasterizer()
    ) -> WidgetCanvasService {
        WidgetCanvasService(
            appGroupContainerURL: containerURL,
            canonicalDrawingURL: canonicalURL,
            rasterizer: rasterizer,
            reloader: reloader
        )
    }

    var payloadURL: URL {
        containerURL.appendingPathComponent("Widget/current.json")
    }

    func url(relativePath: String) -> URL {
        containerURL.appendingPathComponent(relativePath)
    }

    var previewFiles: [URL] {
        let previewsURL = containerURL.appendingPathComponent("Widget/previews", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(
            at: previewsURL,
            includingPropertiesForKeys: nil
        )) ?? []
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

private struct PartialWidgetRasterizer: WidgetDrawingRasterizing {
    @MainActor
    func renderPNG(
        fromDrawingData _: Data,
        canvasSide _: CGFloat,
        pixelWidth: CGFloat
    ) async -> Data? {
        await Task.yield()
        return pixelWidth < 800 ? Data([0x01]) : nil
    }
}

@MainActor
private final class SuspendingFirstWidgetRasterizer: WidgetDrawingRasterizing {
    private var shouldSuspendNextRender = true
    private var didStartFirstRender = false
    private var firstRenderContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func renderPNG(
        fromDrawingData _: Data,
        canvasSide _: CGFloat,
        pixelWidth _: CGFloat
    ) async -> Data? {
        if shouldSuspendNextRender {
            shouldSuspendNextRender = false
            didStartFirstRender = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                firstRenderContinuation = continuation
            }
        }
        return Data([0x01])
    }

    func waitUntilFirstRenderStarts() async {
        guard !didStartFirstRender else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeFirstRender() {
        firstRenderContinuation?.resume()
        firstRenderContinuation = nil
    }
}
