import Foundation
import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

/// Privacy clearing and hiding of the widget copies.
extension WidgetCanvasServiceTests {
    @Test func clearForPrivacyRemovesEverythingAndReloads() async throws {
        let environment = WidgetCanvasTestEnvironment()
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
        let environment = WidgetCanvasTestEnvironment()
        let service = environment.makeService()

        await service.clearForPrivacy()

        #expect(environment.reloader.reloadCount == 0)
    }

    @Test func temporaryPrivacyHidePreservesCanonicalDrawingButRemovesWidgetCopies() async throws {
        let environment = WidgetCanvasTestEnvironment()
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

    @Test func showsSavedDrawingOnlyWhileTheAppCanReadTheWidgetFiles() async throws {
        let environment = WidgetCanvasTestEnvironment()
        let service = environment.makeService()
        #expect(await !service.isShowingSavedDrawing())

        try await service.saveDrawing(
            makeNonEmptyDrawing().dataRepresentation(),
            canvasSize: CGSize(width: 300, height: 300),
            authorName: nil,
            createdAt: Date()
        )
        #expect(await service.isShowingSavedDrawing())

        // An older widget extension left out `canvasSide`, which the app needs.
        var json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: environment.payloadURL)) as? [String: Any]
        )
        json.removeValue(forKey: "canvasSide")
        try JSONSerialization.data(withJSONObject: json).write(to: environment.payloadURL)
        #expect(await !service.isShowingSavedDrawing())

        await service.hideForPrivacy()
        #expect(await !service.isShowingSavedDrawing())
    }
}
