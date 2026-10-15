import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// A draft saved in the background never undoes a newer save or a removal.
@MainActor
struct GameDraftSaveTests {
    private let owner = UUID()
    private let round = UUID()

    private func stores() -> [any GameDrawingStoring] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return [InMemoryGameDrawingStore(), FileGameDrawingStore(directoryURL: directory)]
    }

    @Test func aBackgroundSaveWritesWhenNothingNewerHappened() {
        for store in stores() {
            let ticket = store.beginDraftSave(ownerUserID: owner, roundID: round)
            store.saveDraft(Data([1]), ownerUserID: owner, roundID: round, ticket: ticket)

            #expect(store.draft(ownerUserID: owner, roundID: round) == Data([1]))
        }
    }

    @Test func aLaterBackgroundSaveWinsEvenWhenTheEarlierOneFinishesLast() {
        for store in stores() {
            let earlier = store.beginDraftSave(ownerUserID: owner, roundID: round)
            let later = store.beginDraftSave(ownerUserID: owner, roundID: round)
            store.saveDraft(Data([2]), ownerUserID: owner, roundID: round, ticket: later)
            store.saveDraft(Data([1]), ownerUserID: owner, roundID: round, ticket: earlier)

            #expect(store.draft(ownerUserID: owner, roundID: round) == Data([2]))
        }
    }

    @Test func aRemovalStopsASaveThatIsStillOnItsWay() {
        for store in stores() {
            let ticket = store.beginDraftSave(ownerUserID: owner, roundID: round)
            store.removeDraft(ownerUserID: owner, roundID: round)
            store.saveDraft(Data([1]), ownerUserID: owner, roundID: round, ticket: ticket)

            #expect(store.draft(ownerUserID: owner, roundID: round) == nil)
        }
    }

    @Test func aSaveRightAwayStopsASaveThatIsStillOnItsWay() {
        for store in stores() {
            let ticket = store.beginDraftSave(ownerUserID: owner, roundID: round)
            store.saveDraft(Data([2]), ownerUserID: owner, roundID: round)
            store.saveDraft(Data([1]), ownerUserID: owner, roundID: round, ticket: ticket)

            #expect(store.draft(ownerUserID: owner, roundID: round) == Data([2]))
        }
    }

    @Test func clearingEverythingStopsASaveThatIsStillOnItsWay() {
        for store in stores() {
            let ticket = store.beginDraftSave(ownerUserID: owner, roundID: round)
            store.clearAll()
            store.saveDraft(Data([1]), ownerUserID: owner, roundID: round, ticket: ticket)

            #expect(store.draft(ownerUserID: owner, roundID: round) == nil)
        }
    }

    @Test func otherRoundsDoNotStopASave() {
        for store in stores() {
            let ticket = store.beginDraftSave(ownerUserID: owner, roundID: round)
            store.saveDraft(Data([9]), ownerUserID: owner, roundID: UUID())
            store.saveDraft(Data([1]), ownerUserID: owner, roundID: round, ticket: ticket)

            #expect(store.draft(ownerUserID: owner, roundID: round) == Data([1]))
        }
    }

    @Test func savingInTheBackgroundStoresTheCanonicalDrawing() async throws {
        let store = InMemoryGameDrawingStore()
        let side = GameCanvas.canonicalSide * 2
        let drawing = PKDrawing(strokes: [ReplayFixtures.stroke(created: 0, offsets: [0, 1, 2], y: 100)])

        store.saveDraftInBackground(drawing, fromSide: side, ownerUserID: owner, roundID: round)

        var data: Data?
        for _ in 0..<100 where data == nil {
            data = store.draft(ownerUserID: owner, roundID: round)
            try await Task.sleep(for: .milliseconds(20))
        }
        let saved = try PKDrawing(data: try #require(data))
        let expected = GameCanvas.canonical(drawing, fromSide: side)
        #expect(saved.paeoniaContentSignature == expected.paeoniaContentSignature)
    }
}
