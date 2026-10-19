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
}
