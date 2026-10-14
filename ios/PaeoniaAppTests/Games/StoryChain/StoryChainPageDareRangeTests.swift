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

    @Test func findsTheWordIgnoringCase() {
        #expect(found("lighthouse", in: "She climbed the Lighthouse at dawn.") == "Lighthouse")
        #expect(found("LIGHTHOUSE", in: "She climbed the lighthouse at dawn.") == "lighthouse")
    }

    @Test func findsNorwegianLettersIgnoringCase() {
        #expect(found("smørbrød", in: "Han spiste SMØRBRØD i går.") == "SMØRBRØD")
        #expect(found("åpning", in: "Åpningen var stille.") == "Åpning")
        #expect(found("ærlig", in: "Det var Ærlig ment.") == "Ærlig")
    }

    @Test func aWordInsideALongerWordCounts() {
        #expect(found("hund", in: "Han fant gårdshunden i går.") == "hund")
    }

    @Test func underlinesTheFirstPlaceOnly() {
        let text = "Hund og hund og hund."
        let range = StoryChainDareRange.range(of: "hund", in: text)

        #expect(range.map { text.distance(from: text.startIndex, to: $0.lowerBound) } == 0)
        #expect(StoryChainDareRange.characterRange(of: "hund", in: text) == 0..<4)
    }

    @Test func noMatchOrNoWordGivesNoRange() {
        #expect(StoryChainDareRange.range(of: "anchor", in: "Nothing here.") == nil)
        #expect(StoryChainDareRange.range(of: "", in: "Nothing here.") == nil)
        #expect(StoryChainDareRange.characterRange(of: nil, in: "Nothing here.") == nil)
    }

    @Test func theCharacterRangeCountsWhatAPersonSees() {
        // "På " is 3 characters, so "hund" sits at 3 to 7 even though "å" has accents.
        #expect(StoryChainDareRange.characterRange(of: "hund", in: "På hund") == 3..<7)
        // An emoji is one character, so it does not push the range further.
        #expect(StoryChainDareRange.characterRange(of: "moon", in: "A 🌙 moon") == 4..<8)
    }

    // MARK: Words

    @Test func cutsALineIntoWordsThatKeepTheirTrailingSpace() {
        let characters = Array("It opened nothing. ")
        let words = StoryChainWords.ranges(in: characters).map { String(characters[$0]) }

        #expect(words == ["It ", "opened ", "nothing. "])
    }

    @Test func theWordsTogetherCoverTheWholeText() {
        let characters = Array("  Two  spaces,\tand a tab\n")
        let ranges = StoryChainWords.ranges(in: characters)

        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == characters.count)
        for (current, next) in zip(ranges, ranges.dropFirst()) {
            #expect(current.upperBound == next.lowerBound)
        }
        #expect(ranges.count == 5)
    }

    @Test func countsWords() {
        #expect(StoryChainWords.count(in: "One") == 1)
        #expect(StoryChainWords.count(in: "Det var en gang.") == 4)
        #expect(StoryChainWords.count(in: "   ") == 1)
        #expect(StoryChainWords.count(in: "") == 0)
    }

    // MARK: Paragraph

    @Test func linesFlowTogetherWithASpaceAfterEach() {
        let content = StoryChainPageContent(
            opening: "The bus left early.",
            lines: [line("Nobody got on."), line("Then a dog did.", mine: false)]
        )

        let text = StoryChainParagraph.segments(for: content).map(\.string).joined()

        #expect(text == "The bus left early. Nobody got on. Then a dog did. ")
    }

    @Test func theOpeningIsMutedAndBelongsToNoLine() {
        let content = StoryChainPageContent(opening: "The bus left early.", lines: [line("Nobody got on.")])

        let opening = StoryChainParagraph.segments(for: content).first

        #expect(opening?.role == .opening)
        #expect(opening?.lineID == nil)
    }

    @Test func eachPartnerHasTheirOwnInk() {
        let mine = line("I wrote this.", mine: true)
        let theirs = line("They wrote this.", mine: false)

        #expect(StoryChainParagraph.segments(for: mine).allSatisfy { $0.role == .mine && $0.lineID == mine.id })
        #expect(StoryChainParagraph.segments(for: theirs).allSatisfy { $0.role == .partner && $0.lineID == theirs.id })
    }

    @Test func everyWordCarriesItsPlaceInTheLine() {
        let segments = StoryChainParagraph.segments(for: line("Det var en gang."))

        #expect(segments.map(\.string) == ["Det ", "var ", "en ", "gang. "])
        #expect(segments.map(\.wordIndex) == [0, 1, 2, 3])
        #expect(segments.allSatisfy { $0.wordCount == 4 })
    }

    @Test func theDaredWordSplitsOutOfALongerWord() {
        let segments = StoryChainParagraph.segments(for: line("Han fant gårdshunden i går.", dare: "hund"))

        #expect(segments.map(\.string) == ["Han ", "fant ", "gårds", "hund", "en ", "i ", "går. "])
        #expect(segments.map(\.isDared) == [false, false, false, true, false, false, false])
        // The three pieces of the long word are the same word.
        #expect(segments[2...4].allSatisfy { $0.wordIndex == 2 })
        #expect(segments.allSatisfy { $0.wordCount == 5 })
    }

    @Test func aDaredWordAtTheEndKeepsTheFullStopAndTheSpaceOutsideTheUnderline() {
        let segments = StoryChainParagraph.segments(for: line("Look at the Moon.", dare: "moon"))

        #expect(segments.map(\.string) == ["Look ", "at ", "the ", "Moon", ". "])
        #expect(segments.filter(\.isDared).map(\.string) == ["Moon"])
    }

    @Test func aLineWithoutADareHasNoUnderline() {
        #expect(!StoryChainParagraph.segments(for: line("Plain words.")).contains { $0.isDared })
        // A dare the line does not contain underlines nothing.
        #expect(!StoryChainParagraph.segments(for: line("Plain words.", dare: "anchor")).contains { $0.isDared })
    }

    @Test func thePartnersDraftEndsTheParagraphWithACaret() {
        let content = StoryChainPageContent(
            lines: [line("First.")],
            ghost: StoryChainGhost(text: "And then the\nlight", isLast: false)
        )

        let segments = StoryChainParagraph.segments(for: content)

        #expect(segments.suffix(2).map(\.role) == [.ghost, .caret])
        #expect(segments.suffix(2).map(\.string) == ["And then the light", StoryChainParagraph.caret])
        #expect(segments.suffix(2).allSatisfy { $0.lineID == nil })
    }

    @Test func anEmptyDraftShowsOnlyTheCaretAndNoDraftShowsNothing() {
        let empty = StoryChainPageContent(lines: [], ghost: StoryChainGhost(text: "", isLast: false))
        let none = StoryChainPageContent(lines: [line("First.")])

        #expect(StoryChainParagraph.segments(for: empty).map(\.role) == [.caret])
        #expect(!StoryChainParagraph.segments(for: none).contains { $0.role == .ghost || $0.role == .caret })
    }

    // MARK: VoiceOver

    @Test func eachLineIsReadWithItsWriter() {
        let theirs = line("Then a dog did.", mine: false, author: "Robin")
        let mine = line("Nobody got on.", mine: true, author: "Sam")

        #expect(StoryChainPageText.spokenText(for: theirs, youLabel: "You") == "Robin: Then a dog did.")
        #expect(StoryChainPageText.spokenText(for: mine, youLabel: "You") == "You: Nobody got on.")
        #expect(
            StoryChainPageText.spokenText(opening: "The bus left early.", openingLabel: "Opening")
                == "Opening: The bus left early."
        )
    }

    // MARK: Caret

    @Test func theCaretBlinksOncePerSecondAndStaysInRange() {
        let start = Date(timeIntervalSinceReferenceDate: 100)

        for step in 0..<20 {
            let moment = start.addingTimeInterval(Double(step) * 0.05)
            let value = StoryChainCaret.opacity(at: moment)
            #expect(value >= 0 && value <= 1)
            #expect(abs(value - StoryChainCaret.opacity(at: moment.addingTimeInterval(1))) < 1e-6)
        }
        #expect(StoryChainCaret.opacity(at: start) == 1)
        #expect(StoryChainCaret.opacity(at: start.addingTimeInterval(0.5)) == 0)
    }
}
