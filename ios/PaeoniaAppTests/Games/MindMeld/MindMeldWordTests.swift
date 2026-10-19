import Foundation
import Testing
@testable import PaeoniaApp

/// The word rules, the match key, and the "Surprise me" lists.
struct MindMeldWordTests {
    private func issue(_ text: String, used: [String: String] = [:]) -> MindMeldWordIssue? {
        MindMeldWord.validate(text, used: used)
    }

    // MARK: Rules

    @Test func ordinaryWordsAndPhrasesPass() {
        let words = ["ocean", "Ice cream", "New York", "rock 'n' roll", "ice-cream", "L’amour", "R2D2", "blåbær"]
        for text in words + ["Привет", "寿司"] {
            #expect(issue(text) == nil, "\(text)")
        }
    }

    @Test func thirtyCharactersPassAndThirtyOneAreTooLong() {
        #expect(issue(String(repeating: "a", count: 30)) == nil)
        #expect(issue(String(repeating: "a", count: 31)) == .tooLong)
    }

    @Test func lengthCountsCodePointsLikeTheServer() {
        // Sixteen letters, each an "e" and a combining accent, are 32 code points.
        #expect(issue(String(repeating: "e\u{301}", count: 16)) == .tooLong)
        #expect(issue(String(repeating: "e\u{301}", count: 15)) == nil)
    }

    @Test func threeWordsPassAndFourAreTooMany() {
        #expect(issue("one two three") == nil)
        #expect(issue("one   two \n three") == nil)
        #expect(issue("one two three four") == .tooManyWords)
    }

    @Test func aWordNeedsALetter() {
        #expect(issue("123") == .noLetters)
        #expect(issue("-") == .noLetters)
        #expect(issue("'") == .noLetters)
        #expect(issue("1 2 3") == .noLetters)
    }

    @Test func charactersOtherThanLettersNumbersSpacesHyphensAndApostrophesAreRefused() {
        for text in ["hello!", "a_b", "a/b", "ok?", "a.b", "🙂", "dog 🐶", "a@b", "(x)", "a–b"] {
            #expect(issue(text) == .badCharacters, "\(text)")
        }
    }

    // MARK: Repeats

    @Test func aRepeatNamesTheEarlierWordAsItWasSaid() {
        let used = ["icecream": "Ice cream", "ocean": "OCEAN"]

        #expect(issue("ice-cream", used: used) == .repeatOf("Ice cream"))
        #expect(issue("  Ocean ", used: used) == .repeatOf("OCEAN"))
        #expect(issue("ICE CREAM", used: used) == .repeatOf("Ice cream"))
    }

    @Test func aNearMissOfAnEarlierWordIsNotARepeat() {
        let used = ["dog": "dog"]

        #expect(issue("dogs", used: used) == nil)
        #expect(issue("cat", used: used) == nil)
    }

    @Test func theUsedWordsOfAGameComeFromRevealedRoundsOnly() {
        let game = RemoteMindMeldGame(
            id: UUID(),
            gameNumber: 1,
            state: .playing,
            endReason: nil,
            endedByUserID: nil,
            endedAt: nil,
            maxRounds: 10,
            myEndSeenAt: nil,
            meldNumber: nil,
            isRecord: false,
            createdByUserID: UUID(),
            createdAt: Date(),
            updatedAt: Date(),
            version: 1,
            rounds: [
                round(1, state: .revealed, mine: "Ocean", theirs: "sushi"),
                round(2, state: .revealed, mine: "Salt Water", theirs: "ocean"),
                // The open round holds a word this person locked in. It is not said yet.
                round(3, state: .open, mine: "fish", theirs: nil)
            ]
        )

        #expect(game.usedWords == ["ocean": "Ocean", "sushi": "sushi", "saltwater": "Salt Water"])
    }

    private func round(
        _ number: Int,
        state: MindMeldRoundState,
        mine: String?,
        theirs: String?
    ) -> RemoteMindMeldRound {
        RemoteMindMeldRound(
            id: UUID(),
            roundNumber: number,
            state: state,
            outcome: state == .revealed ? .miss : nil,
            countedByUserID: nil,
            myWord: mine,
            myLockedAt: nil,
            partnerLocked: theirs != nil,
            partnerLockedAt: nil,
            partnerWord: theirs,
            revealedAt: nil,
            myRevealSeenAt: nil
        )
    }

    // MARK: Match key

    @Test func spacesPunctuationAndCaseDoNotChangeTheKey() {
        #expect(MindMeldWord.matchKey("Ice cream") == "icecream")
        // The same order as the server: a ring or diaeresis behind a or o counts
        // even under a second accent.
        #expect(MindMeldWord.matchKey("ǻl") == "aal")
        #expect(MindMeldWord.matchKey("ǟ") == "ae")
        #expect(MindMeldWord.matchKey("a\u{030A}\u{0308}l") == "aal")
        #expect(MindMeldWord.matchKey("Ö") == "oe")
        #expect(MindMeldWord.matchKey("ice-cream") == "icecream")
        #expect(MindMeldWord.matchKey("is krem") == "iskrem")
        #expect(MindMeldWord.matchKey("rock 'n' roll") == "rocknroll")
        #expect(MindMeldWord.matchKey("R2D2") == "r2d2")
    }

    @Test func scandinavianLettersSpellOutAndAccentsDrop() {
        #expect(MindMeldWord.matchKey("Blåbær") == "blaabaer")
        #expect(MindMeldWord.matchKey("Ærlig") == "aerlig")
        #expect(MindMeldWord.matchKey("Ørret") == "oerret")
        #expect(MindMeldWord.matchKey("Äpple") == "aepple")
        #expect(MindMeldWord.matchKey("Öl") == "oel")
        #expect(MindMeldWord.matchKey("café") == "cafe")
        #expect(MindMeldWord.matchKey("Über") == "uber")
        // The same word typed with a combining accent.
        #expect(MindMeldWord.matchKey("cafe\u{301}") == "cafe")
        #expect(MindMeldWord.matchKey("a\u{30A}") == "aa")
    }

    @Test func otherAlphabetsKeepTheirLetters() {
        #expect(MindMeldWord.matchKey("Привет") == "привет")
        #expect(MindMeldWord.matchKey("Ёлка") == "елка")
        #expect(MindMeldWord.matchKey("寿司") == "寿司")
    }

    // MARK: Starter words

    @Test func anExcludedWordIsNeverPicked() {
        var generator = DrawAndGuessSeededGenerator(seed: 1)
        let excluded: Set<String> = [MindMeldWord.matchKey("pizza"), MindMeldWord.matchKey("volcano")]

        for _ in 0..<300 {
            let word = MindMeldStarterWords.random(for: .en, excluding: excluded, using: &generator)
            #expect(!excluded.contains(MindMeldWord.matchKey(word)))
        }
    }

    @Test func withEveryWordExcludedItStillPicksAWord() {
        var generator = DrawAndGuessSeededGenerator(seed: 5)
        let all = Set(MindMeldStarterWords.english.map(MindMeldWord.matchKey))
        let word = MindMeldStarterWords.random(for: .en, excluding: all, using: &generator)

        #expect(MindMeldStarterWords.english.contains(word))
    }
}
