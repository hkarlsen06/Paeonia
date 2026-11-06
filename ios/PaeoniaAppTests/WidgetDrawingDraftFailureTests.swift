import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

@MainActor
struct WidgetDrawingDraftFailureTests {
    @Test func failedDrawingAndDescriptionWriteSurvivesNavigationThenRetryMakesItDurable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A regular file cannot contain the owner's draft directory.
        try Data([1]).write(to: directory)
        let store = FileWidgetDrawingDraftStore(directoryURL: directory)
        let owner = UUID()
        let couple = UUID()
        let original = makeNonEmptyDrawing(seed: 72)
        func model() -> WidgetDrawingViewModel {
            WidgetDrawingViewModel(
                ownerUserID: owner, coupleID: couple,
                service: WidgetCanvasServiceSpy(), uploader: WidgetCanvasUploadSpy(), draftStore: store
            )
        }
        let first = model()
        first.updateDrawing(original)
        first.updateAccessibilityText("A heart under the moon")
        first.persistDraftIfNeeded()
        #expect(first.draftSaveFailed)
        let reopened = model()
        await reopened.loadSavedDrawingIfNeeded()
        #expect(reopened.drawing.strokes.map(\.renderBounds) == original.strokes.map(\.renderBounds))
        #expect(reopened.accessibilityText == "A heart under the moon")
        #expect(reopened.draftSaveFailed)
        try FileManager.default.removeItem(at: directory)
        reopened.retryDraftSave()
        #expect(!reopened.draftSaveFailed)
        let freshStore = FileWidgetDrawingDraftStore(directoryURL: directory)
        let key = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: couple)
        let durable = try #require(freshStore.draft(for: key))
        #expect(try PKDrawing(data: durable).strokes.map(\.renderBounds) == original.strokes.map(\.renderBounds))
        #expect(freshStore.description(for: key) == "A heart under the moon")
    }

    @Test func descriptionWithoutStrokesIsRetainedAndPurgingPreventsAnOldScreenFromRecreatingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([1]).write(to: directory)
        let store = FileWidgetDrawingDraftStore(directoryURL: directory)
        let owner = UUID()
        let key = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: UUID())
        let model = WidgetDrawingViewModel(
            ownerUserID: owner, coupleID: key.coupleID,
            service: WidgetCanvasServiceSpy(), uploader: WidgetCanvasUploadSpy(), draftStore: store
        )
        model.updateAccessibilityText("My next drawing")
        #expect(model.draftSaveFailed)
        #expect(store.description(for: key) == "My next drawing")
        #expect(store.draft(for: WidgetDrawingDraftKey(ownerUserID: UUID(), coupleID: key.coupleID)) == nil)
        store.clearDraft(for: owner)
        model.persistDraftIfNeeded()
        #expect(store.draft(for: key) == nil)
        #expect(store.description(for: key) == nil)
    }
}
