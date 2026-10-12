import Testing
@testable import PaeoniaApp

struct DrawAndGuessCustomWordTests {
    private func failure(_ text: String) -> DrawAndGuessCustomWord.Failure? {
        if case .failure(let failure) = DrawAndGuessCustomWord.validate(text) {
            return failure
        }
        return nil
    }

    private func word(_ text: String) -> String? {
        if case .success(let word) = DrawAndGuessCustomWord.validate(text) {
            return word
        }
        return nil
    }

    @Test func trimsAndCollapsesWhitespaceKeepingCase() {
        #expect(word("  the \t dog\n  mom ") == "the dog mom")
        #expect(word("Hund") == "Hund")
    }

    @Test func lengthBoundsCountLettersNotSpaces() {
        #expect(failure("a") == .tooShort)
        #expect(failure("   ") == .tooShort)
        #expect(failure("") == .tooShort)
        #expect(word("ab") == "ab")
        #expect(word("a b") == "a b")
        #expect(word(String(repeating: "a", count: 20)) == String(repeating: "a", count: 20))
        #expect(failure(String(repeating: "a", count: 21)) == .tooLong)
        #expect(word("aaaaaaaaaa aaaaaaaaaa") == "aaaaaaaaaa aaaaaaaaaa")
        #expect(failure("aaaaaaaaaa aaaaaaaaaaa") == .tooLong)
    }

    @Test func threeWordsAreAllowedFourAreNot() {
        #expect(word("a big dog") == "a big dog")
        #expect(failure("a big red dog") == .tooManyWords)
    }

    @Test func norwegianLettersAreAllowedInEitherCase() {
        #expect(word("blåbær") == "blåbær")
        #expect(word("ØL") == "ØL")
        #expect(word("Ærlig å") == "Ærlig å")
    }

    @Test func decomposedNorwegianLettersAreJoined() {
        let decomposed = "a\u{030A}l"

        #expect(word(decomposed) == "\u{00E5}l")
    }

    @Test(arguments: ["abc1", "a-b", "dog!", "café", "naïve", "ña", "ab😀", "a.b", "a_b", "über", "straße", "漢字ab"])
    func otherCharactersAreRejected(text: String) {
        #expect(failure(text) == .notAllowedCharacter)
    }

    @Test func characterRuleWinsOverLength() {
        #expect(failure("1") == .notAllowedCharacter)
    }
}
