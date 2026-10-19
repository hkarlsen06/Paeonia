import Foundation
import Testing
@testable import PaeoniaApp

/// Where the gold underline goes, how a line is cut into words, and how the
/// lines flow into one paragraph.
@MainActor
struct StoryChainPageDareRangeTests {
    private func line(
        _ text: String,
        mine: Bool = true,
        dare: String? = nil,
        author: String = "Robin"
    ) -> StoryChainPageLine {
        StoryChainPageLine(
            id: UUID(),
            number: 1,
            text: text,
            isMine: mine,
            usedDare: dare,
            authorName: author,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func found(_ word: String, in text: String) -> String? {
        StoryChainDareRange.range(of: word, in: text).map { String(text[$0]) }
    }

    // MARK: Dare range

    @Test func findsNorwegianLettersIgnoringCase() {
        #expect(found("smørbrød", in: "Han spiste SMØRBRØD i går.") == "SMØRBRØD")
        #expect(found("åpning", in: "Åpningen var stille.") == "Åpning")
        #expect(found("ærlig", in: "Det var Ærlig ment.") == "Ærlig")
    }

    @Test func aWordInsideALongerWordCounts() {
        #expect(found("hund", in: "Han fant gårdshunden i går.") == "hund")
    }

    @Test func theCharacterRangeCountsWhatAPersonSees() {
        // "På " is 3 characters, so "hund" sits at 3 to 7 even though "å" has accents.
        #expect(StoryChainDareRange.characterRange(of: "hund", in: "På hund") == 3..<7)
        // An emoji is one character, so it does not push the range further.
        #expect(StoryChainDareRange.characterRange(of: "moon", in: "A 🌙 moon") == 4..<8)
    }

    @Test func theDaredWordSplitsOutOfALongerWord() {
        let segments = StoryChainParagraph.segments(for: line("Han fant gårdshunden i går.", dare: "hund"))

        #expect(segments.map(\.string) == ["Han ", "fant ", "gårds", "hund", "en ", "i ", "går. "])
        #expect(segments.map(\.isDared) == [false, false, false, true, false, false, false])
        // The three pieces of the long word are the same word.
        #expect(segments[2...4].allSatisfy { $0.wordIndex == 2 })
        #expect(segments.allSatisfy { $0.wordCount == 5 })
    }
}
