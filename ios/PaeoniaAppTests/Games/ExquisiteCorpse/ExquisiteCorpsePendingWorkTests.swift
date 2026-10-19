import Foundation
import Testing
@testable import PaeoniaApp

struct ExquisiteCorpsePendingWorkTests {
    private typealias Fixture = ExquisiteCorpseFixture

    @Test func onlyAPartIsAMoveThatWaits() {
        let marks = Fixture.pending(revealsSeen: [Fixture.figureID(1)], stars: [(Fixture.figureID(1), true)])
        let part = Fixture.pending(parts: [Fixture.queuedPart(figure: 2, partIndex: 0)])

        #expect(!marks.isEmpty && !marks.hasMoveWaiting)
        #expect(!part.isEmpty && part.hasMoveWaiting)
    }

    @Test func theLastStarOfAFigureWins() {
        let figure = Fixture.figureID(1)
        let work = Fixture.pending(stars: [(figure, true), (Fixture.figureID(2), true), (figure, false)])

        #expect(work.star(figureID: figure) == false)
        #expect(work.star(figureID: Fixture.figureID(2)) == true)
        #expect(work.star(figureID: Fixture.figureID(3)) == nil)
    }
}
