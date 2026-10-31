import Foundation
import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

struct DrawingCompositionTests {
    @Test func coordinatesFitEveryShapeAtEdgesAndScaleAcrossCanvases() {
        for shape in DrawingComposition.Shape.allCases {
            let small = DrawingComposition.points(shape: shape, x: 100, y: -10, size: 30, side: 200)
            let large = DrawingComposition.points(shape: shape, x: 100, y: -10, size: 30, side: 400)
            #expect(!small.isEmpty)
            #expect(small.allSatisfy { $0.x >= 0 && $0.x <= 200 && $0.y >= 0 && $0.y <= 200 })
            for (first, second) in zip(small, large) {
                #expect(abs(first.x * 2 - second.x) < 0.001)
                #expect(abs(first.y * 2 - second.y) < 0.001)
            }
        }
        #expect(DrawingComposition.points(shape: .circle, x: .nan, y: 50, size: 20, side: 200).isEmpty)
    }

    @Test func strokesSurviveTheRealDraftFormatAndEditingKeepsOtherMarks() throws {
        let circle = try #require(DrawingComposition.stroke(
            shape: .circle, x: 30, y: 40, size: 20, side: 300, color: .red
        ))
        let line = try #require(DrawingComposition.stroke(
            shape: .verticalLine, x: 70, y: 50, size: 40, side: 300, color: .blue
        ))
        let first = DrawingComposition.replacing(nil, in: PKDrawing(), with: circle)
        let second = DrawingComposition.replacing(nil, in: first, with: line)
        let restored = try PKDrawing(data: second.dataRepresentation())
        #expect(restored.strokes.count == 2)
        let edited = DrawingComposition.replacing(0, in: restored, with: line)
        #expect(edited.strokes.count == 2)
        #expect(edited.strokes[1].path.count == line.path.count)
        let removed = DrawingComposition.replacing(0, in: edited, with: nil)
        #expect(removed.strokes.count == 1)
        #expect(removed.strokes[0].renderBounds == edited.strokes[1].renderBounds)
    }
    @Test func generatedGeometryRemainsReadableAfterStorageAndScaling() throws {
        for shape in DrawingComposition.Shape.allCases {
            let stroke = try #require(DrawingComposition.stroke(
                shape: shape, x: 50, y: 50, size: 30, side: 300, color: .red
            ))
            let encoded = PKDrawing(strokes: [stroke]).dataRepresentation()
            let restored = try PKDrawing(data: encoded)
                .transformed(using: CGAffineTransform(scaleX: 2, y: 2))
            #expect(DrawingComposition.shape(of: restored.strokes[0]) == shape)
        }
    }

    @MainActor
    @Test func descriptionsShareDraftStorageAndPrivacyPurge() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileWidgetDrawingDraftStore(directoryURL: directory)
        let key = WidgetDrawingDraftKey(ownerUserID: UUID(), coupleID: UUID())
        store.setDraft(Data([1, 2]), for: key)
        store.setDescription("Two circles", for: key)
        let reopened = FileWidgetDrawingDraftStore(directoryURL: directory)
        #expect(reopened.description(for: key) == "Two circles")
        #expect(reopened.description(for: WidgetDrawingDraftKey(ownerUserID: UUID(), coupleID: key.coupleID)) == nil)
        store.clearDraft(for: key.ownerUserID)
        #expect(reopened.description(for: key) == nil)
    }

}
