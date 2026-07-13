import Foundation
import UIKit
import Testing
@testable import PaeoniaApp

struct HomeWidgetPreviewLoaderTests {
    @Test func loadReturnsNilImageWhenNoPayloadExists() {
        let environment = TestEnvironment()

        let content = environment.makeLoader().load()

        #expect(content.image == nil)
    }

    @Test func loadReturnsPreviewImageForNormalPayload() throws {
        let environment = TestEnvironment()
        try environment.writePreview(named: "systemSmall.png")
        try environment.writePayload(
            previews: ["systemSmall": "Widget/previews/systemSmall.png"]
        )

        let content = environment.makeLoader().load()

        #expect(content.image != nil)
    }

    @Test func loadFallsBackToLargePreviewWhenSmallMissing() throws {
        let environment = TestEnvironment()
        try environment.writePreview(named: "systemLarge.png")
        try environment.writePayload(
            previews: ["systemLarge": "Widget/previews/systemLarge.png"]
        )

        let content = environment.makeLoader().load()

        #expect(content.image != nil)
    }

    @Test func loadIgnoresRedactedPayload() throws {
        let environment = TestEnvironment()
        try environment.writePreview(named: "systemSmall.png")
        try environment.writePayload(
            previews: ["systemSmall": "Widget/previews/systemSmall.png"],
            privacyMode: .redacted,
            isRedacted: true
        )

        let content = environment.makeLoader().load()

        #expect(content.image == nil)
    }

    @Test func loadReturnsNilImageWhenPreviewFileMissing() throws {
        let environment = TestEnvironment()
        try environment.writePayload(
            previews: ["systemSmall": "Widget/previews/systemSmall.png"]
        )

        let content = environment.makeLoader().load()

        #expect(content.image == nil)
    }

    @Test func loadIgnoresFutureSchemaPayload() throws {
        let environment = TestEnvironment()
        try environment.writePreview(named: "systemSmall.png")
        try environment.writePayload(
            previews: ["systemSmall": "Widget/previews/systemSmall.png"],
            schemaVersion: WidgetSharePayload.currentSchemaVersion + 1
        )

        let content = environment.makeLoader().load()

        #expect(content.image == nil)
    }

    @Test func loadRejectsPreviewPathTraversal() throws {
        let environment = TestEnvironment()
        try environment.writePreview(named: "systemSmall.png")
        try environment.writePayload(
            previews: ["systemSmall": "Widget/previews/../previews/systemSmall.png"]
        )

        let content = environment.makeLoader().load()

        #expect(content.image == nil)
    }

    @Test func preferredPreviewPathPrefersSmall() {
        let path = HomeWidgetPreviewLoader.preferredPreviewPath(in: [
            "systemLarge": "large.png",
            "systemSmall": "small.png",
        ])

        #expect(path == "small.png")
    }
}

private struct TestEnvironment {
    let containerURL: URL

    init() {
        containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeWidgetPreviewLoaderTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
    }

    func makeLoader() -> HomeWidgetPreviewLoader {
        HomeWidgetPreviewLoader(containerURL: containerURL)
    }

    func writePreview(named fileName: String) throws {
        let previewsURL = containerURL.appendingPathComponent("Widget/previews", isDirectory: true)
        try FileManager.default.createDirectory(at: previewsURL, withIntermediateDirectories: true)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let data = try #require(image.pngData())
        try data.write(to: previewsURL.appendingPathComponent(fileName))
    }

    func writePayload(
        previews: [String: String],
        privacyMode: WidgetSharePrivacyMode = .normal,
        isRedacted: Bool = false,
        schemaVersion: Int = WidgetSharePayload.currentSchemaVersion
    ) throws {
        var payload = WidgetSharePayload(
            revisionID: UUID().uuidString,
            authorName: "Hjalmar",
            createdAt: Date(),
            renderedAt: Date(),
            contentHash: "sha256-test",
            previews: previews
        )
        payload.privacyMode = privacyMode
        payload.isRedacted = isRedacted
        payload.schemaVersion = schemaVersion

        let payloadURL = containerURL.appendingPathComponent("Widget/current.json")
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try WidgetSharePayload.encoder().encode(payload).write(to: payloadURL)
    }
}
