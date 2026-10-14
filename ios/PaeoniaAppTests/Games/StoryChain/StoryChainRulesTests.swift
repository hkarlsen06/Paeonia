import Foundation
import Testing
@testable import PaeoniaApp

/// The Story Chain rules the phone and the server both check. The server tests
/// the same rules in `backend/convex/lib/storyChain.test.ts`, with the same
/// examples where they overlap.
struct StoryChainRulesTests {
    private typealias Rules = StoryChainRules

    // MARK: Text

    @Test func collapsesEveryRunOfWhitespaceAndLineBreaksToOneSpace() {
        #expect(Rules.normalizeText("  The   night\n\nbus\t left \r\n early.  ") == "The night bus left early.")
        #expect(Rules.normalizeText("a\u{00A0}\u{2003}\u{3000}b") == "a b")
        #expect(Rules.normalizeText(" \n\t ").isEmpty)
        #expect(Rules.normalizeText("").isEmpty)
    }

    @Test func whitespaceIsTheSetTheServerUses() {
        // JavaScript's `\s` has U+FEFF and not U+0085.
        #expect(Rules.normalizeText("\u{FEFF}hi\u{FEFF}") == "hi")
        #expect(Rules.normalizeText("a\u{0085}b") == "a\u{0085}b")
        #expect(Rules.normalizeText("a\u{200D}b") == "a\u{200D}b")
    }

    @Test func aLineHasTwoToTwoHundredFortyCodePoints() {
        #expect(!Rules.isValidLine(""))
        #expect(!Rules.isValidLine("a"))
        #expect(!Rules.isValidLine("  a  "))
        #expect(Rules.isValidLine("ab"))
        #expect(Rules.isValidLine("a b"))
        #expect(!Rules.isValidLine(" \n "))
    }

    @Test func aLineOfEmojiIsCountedByCodePointAtTheLimit() {
        let atLimit = String(repeating: "\u{1F600}", count: 240)

        #expect(Rules.length(atLimit) == 240)
        #expect(Rules.isValidLine(atLimit))
        #expect(Rules.length(atLimit + "\u{1F600}") == 241)
        #expect(!Rules.isValidLine(atLimit + "\u{1F600}"))
    }

    @Test func aJoinedEmojiCountsAsAllItsCodePoints() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let atLimit = String(repeating: "a", count: 235) + family

        #expect(Rules.length(family) == 5)
        #expect(Rules.isValidLine(atLimit))
        #expect(!Rules.isValidLine(atLimit + "a"))
    }

    @Test func theLengthIsCountedAfterNormalizing() {
        let padded = "  " + String(repeating: "a", count: 240) + "\n\n"

        #expect(Rules.length(padded) == 240)
        #expect(Rules.isValidLine(padded))
        #expect(Rules.length("a\n\n\n\nb") == 3)
    }

    @Test func aTitleHasOneToFortyCodePoints() {
        #expect(Rules.normalizedTitle("  The night bus \n") == "The night bus")
        #expect(Rules.normalizedTitle("A\n\nB") == "A B")
        #expect(Rules.normalizedTitle("") == nil)
        #expect(Rules.normalizedTitle(" \n ") == nil)
        #expect(Rules.normalizedTitle(String(repeating: "a", count: 40)) != nil)
        #expect(Rules.normalizedTitle(String(repeating: "a", count: 41)) == nil)
        #expect(Rules.normalizedTitle(String(repeating: "\u{1F600}", count: 40)) != nil)
        #expect(Rules.normalizedTitle(String(repeating: "\u{1F600}", count: 41)) == nil)
    }

    @Test func aLiveDraftIsCutAtTheLineLimitAndOtherwiseLeftAsTyped() {
        let long = String(repeating: "\u{1F600}", count: 300)

        #expect(Rules.truncated(long).unicodeScalars.count == 240)
        #expect(Rules.truncated("short") == "short")
        #expect(Rules.truncated("  keep   spaces \n") == "  keep   spaces \n")
    }

    // MARK: Dare word

    @Test func aLineUsesTheDareWhenItContainsTheWordInAnyCase() {
        #expect(Rules.lineUses("Hunden løp", dare: "hund"))
        #expect(Rules.lineUses("Alle elsket gårdshunden.", dare: "hund"))
        #expect(Rules.lineUses("HAN SPISTE SMØRBRØD", dare: "smørbrød"))
        #expect(Rules.lineUses("Hun spiste smørbrød.", dare: "SMØRBRØD"))
        #expect(Rules.lineUses("The LIGHTHOUSE blinked.", dare: "lighthouse"))
        #expect(Rules.lineUses("They climbed the lighthouses.", dare: "Lighthouse"))
        #expect(Rules.lineUses("Ære være brunosten.", dare: "ÆRE"))
        #expect(Rules.lineUses("Smørbrødene var borte.", dare: "smørbrød"))
        #expect(!Rules.lineUses("Hun løp hjem.", dare: "hund"))
        #expect(!Rules.lineUses("Katten løp over tunet.", dare: "hund"))
        #expect(!Rules.lineUses("Hu nd", dare: "hund"))
        #expect(!Rules.lineUses("", dare: "hund"))
    }

    @Test func theDareCheckIgnoresHowAnAccentIsStored() {
        let composed = "caf\u{E9}"
        let decomposed = "cafe\u{301}"

        #expect(Rules.lineUses("We met at the \(decomposed).", dare: composed))
        #expect(Rules.lineUses("We met at the \(composed).", dare: decomposed))
        #expect(Rules.lineUses("WE MET AT THE CAFE\u{301}.", dare: composed))
        #expect(!Rules.lineUses("We met at the cafe.", dare: composed))
    }

    @Test func aDareWordIsOneWordOfLettersInNFCAndLowercase() {
        #expect(Rules.normalizedDareWord("lighthouse") == "lighthouse")
        #expect(Rules.normalizedDareWord("  Caf\u{E9} ") == "caf\u{E9}")
        #expect(Rules.normalizedDareWord("SMØRBRØD") == "smørbrød")
        #expect(Rules.normalizedDareWord("Åse") == "åse")
        #expect(Rules.normalizedDareWord("ÆØÅ") == "æøå")
        #expect(Rules.normalizedDareWord("cafe\u{301}") == "caf\u{E9}")
        #expect(Rules.normalizedDareWord("\u{65E5}\u{672C}") == "\u{65E5}\u{672C}")
    }

    @Test func aDareWordWithAnythingButLettersIsRejected() {
        #expect(Rules.normalizedDareWord("light house") == nil)
        #expect(Rules.normalizedDareWord("two\nwords") == nil)
        #expect(Rules.normalizedDareWord("abc123") == nil)
        #expect(Rules.normalizedDareWord("42") == nil)
        #expect(Rules.normalizedDareWord("x-ray") == nil)
        #expect(Rules.normalizedDareWord("don't") == nil)
        #expect(Rules.normalizedDareWord("hund!") == nil)
        #expect(Rules.normalizedDareWord("\u{1F600}\u{1F600}") == nil)
        // A mark with no letter of its own to join is not a letter.
        #expect(Rules.normalizedDareWord("ab\u{301}") == nil)
    }

    @Test func aDareWordHasTwoToTwentyLetters() {
        #expect(Rules.normalizedDareWord("") == nil)
        #expect(Rules.normalizedDareWord("   ") == nil)
        #expect(Rules.normalizedDareWord("a") == nil)
        #expect(Rules.normalizedDareWord("ab") == "ab")
        #expect(Rules.normalizedDareWord(String(repeating: "a", count: 20)) != nil)
        #expect(Rules.normalizedDareWord(String(repeating: "a", count: 21)) == nil)
        #expect(Rules.normalizedDareWord(String(repeating: "\u{E9}", count: 20)) != nil)
        #expect(Rules.normalizedDareWord(String(repeating: "\u{E9}", count: 21)) == nil)
    }

    // MARK: Ending

    @Test func theWriterCanEndFromLineEightAndMustEndAtLineTwenty() {
        #expect(!Rules.canEnd(lineNumber: 1))
        #expect(!Rules.canEnd(lineNumber: 7))
        #expect(Rules.canEnd(lineNumber: 8))
        #expect(Rules.canEnd(lineNumber: 19))
        #expect(Rules.canEnd(lineNumber: 20))
        #expect(!Rules.mustEnd(lineNumber: 1))
        #expect(!Rules.mustEnd(lineNumber: 19))
        #expect(Rules.mustEnd(lineNumber: 20))
    }

    @Test func theLimitsAreTheServers() {
        #expect(Rules.minLineLength == 2)
        #expect(Rules.maxLineLength == 240)
        #expect(Rules.counterThreshold == 200)
        #expect(Rules.endFromLine == 8)
        #expect(Rules.maxLines == 20)
        #expect(Rules.maxTitleLength == 40)
        #expect(Rules.dareWordLength == 2...20)
    }

    // MARK: Composer

    @Test func aDraftWithoutADareCanBeSentWhenItsLengthIsRight() {
        let draft = StoryChainLineCheck(draft: "  The   night bus  ")

        #expect(draft.text == "The night bus")
        #expect(draft.length == 13)
        #expect(draft.usesDare == nil)
        #expect(!draft.isTooShort)
        #expect(!draft.isTooLong)
        #expect(!draft.showsCounter)
        #expect(draft.canSend)
        #expect(!StoryChainLineCheck(draft: "").canSend)
        #expect(StoryChainLineCheck(draft: "a").isTooShort)
        #expect(!StoryChainLineCheck(draft: " a \n").canSend)
    }

    @Test func aDraftWaitsForTheDareWord() {
        let missing = StoryChainLineCheck(draft: "The bus left early.", dare: "lighthouse")
        let used = StoryChainLineCheck(draft: "The Lighthouse was dark.", dare: "LIGHTHOUSE")
        let tooShort = StoryChainLineCheck(draft: "x", dare: "x")

        #expect(missing.usesDare == false)
        #expect(!missing.canSend)
        #expect(used.usesDare == true)
        #expect(used.canSend)
        #expect(tooShort.usesDare == true)
        #expect(!tooShort.canSend)
    }

    @Test func theCounterShowsAfterTwoHundredAndSendingStopsAfterTwoHundredForty() {
        func check(_ count: Int) -> StoryChainLineCheck {
            StoryChainLineCheck(draft: String(repeating: "a", count: count))
        }

        #expect(!check(200).showsCounter)
        #expect(check(201).showsCounter)
        #expect(check(240).canSend)
        #expect(!check(240).isTooLong)
        #expect(check(241).isTooLong)
        #expect(!check(241).canSend)
    }
}
