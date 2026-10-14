import Foundation
import Testing
@testable import PaeoniaApp

struct ExquisiteCorpsePendingWorkTests {
    private typealias Fixture = ExquisiteCorpseFixture

    @Test func nothingQueuedIsEmptyAndWaitsForNothing() {
        let work = ExquisiteCorpsePendingWork.none

        #expect(work.isEmpty)
        #expect(!work.hasMoveWaiting)
        #expect(!work.lastSendFailedWhileOnline && !work.hasFailedMoveAttempt)
    }

    @Test func onlyAPartIsAMoveThatWaits() {
        let marks = Fixture.pending(revealsSeen: [Fixture.figureID(1)], stars: [(Fixture.figureID(1), true)])
        let part = Fixture.pending(parts: [Fixture.queuedPart(figure: 2, partIndex: 0)])

        #expect(!marks.isEmpty && !marks.hasMoveWaiting)
        #expect(!part.isEmpty && part.hasMoveWaiting)
    }

    @Test func aRevealSeenMarkBelongsToItsFigure() {
        let work = Fixture.pending(revealsSeen: [Fixture.figureID(1)])

        #expect(work.hasRevealSeen(figureID: Fixture.figureID(1)))
        #expect(!work.hasRevealSeen(figureID: Fixture.figureID(2)))
    }

    @Test func theLastStarOfAFigureWins() {
        let figure = Fixture.figureID(1)
        let work = Fixture.pending(stars: [(figure, true), (Fixture.figureID(2), true), (figure, false)])

        #expect(work.star(figureID: figure) == false)
        #expect(work.star(figureID: Fixture.figureID(2)) == true)
        #expect(work.star(figureID: Fixture.figureID(3)) == nil)
    }

    @Test func thePayloadsSurviveBeingStoredAsJSON() throws {
        let part = Fixture.queuedPart(figure: 1, partIndex: 1, idea: Fixture.idea("a frog"))
        let legs = Fixture.queuedPart(figure: 2, partIndex: 2)
        let seen = ExquisiteCorpseRevealSeenPayload(figureID: Fixture.figureID(1), createdAt: Fixture.now)
        let star = ExquisiteCorpseStarPayload(figureID: Fixture.figureID(1), starred: true, createdAt: Fixture.now)

        #expect(try roundTrip(part) == part)
        #expect(try roundTrip(legs) == legs)
        #expect(try roundTrip(seen) == seen)
        #expect(try roundTrip(star) == star)
        // The legs have no strip.
        #expect(legs.strip == nil)
        #expect(part.strip != nil)
    }

    private func roundTrip<Payload: Codable>(_ payload: Payload) throws -> Payload {
        try JSONDecoder().decode(Payload.self, from: JSONEncoder().encode(payload))
    }
}
