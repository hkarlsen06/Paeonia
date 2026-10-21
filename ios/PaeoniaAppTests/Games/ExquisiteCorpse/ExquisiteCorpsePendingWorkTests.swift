import Foundation
import Testing
@testable import PaeoniaApp

struct ExquisiteCorpsePendingWorkTests {
    private typealias Fixture = ExquisiteCorpseFixture

    @Test func onlyAPartIsAMoveThatWaits() {
        let marks = Fixture.pending(revealsSeen: [Fixture.figureID(1)])
        let part = Fixture.pending(parts: [Fixture.queuedPart(figure: 2, partIndex: 0)])

        #expect(!marks.isEmpty && !marks.hasMoveWaiting)
        #expect(!part.isEmpty && part.hasMoveWaiting)
    }
}
