import Testing
@testable import PaeoniaApp

struct DrawAndGuessTilesTests {
    private func letters(_ tiles: [DrawAndGuessTile]) -> [Character] {
        tiles.map(\.letter)
    }

    private func counts(_ characters: [Character]) -> [Character: Int] {
        characters.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    @Test func sameSeedGivesSameTiles() {
        let first = DrawAndGuessTiles.make(answer: "ice cream", language: .en, seed: "round-1")
        let second = DrawAndGuessTiles.make(answer: "ice cream", language: .en, seed: "round-1")

        #expect(first == second)
    }

    @Test func generatorOutputNeverChanges() {
        // Pins the generator so a change that would split the two phones fails.
        var generator = DrawAndGuessSeededGenerator(seed: 0)
        #expect(generator.next() == 0xe220_a839_7b1d_cdaf)
        #expect(generator.next() == 0x6e78_9e6a_a1b9_65f4)
        var textSeeded = DrawAndGuessSeededGenerator(seed: "")
        var numberSeeded = DrawAndGuessSeededGenerator(seed: 0xcbf2_9ce4_8422_2325)
        #expect(textSeeded.next() == numberSeeded.next())
    }

    @Test func differentSeedsShuffleDifferently() {
        let seeds = (0..<20).map { "round-\($0)" }
        let arrangements = Set(seeds.map { seed in
            String(letters(DrawAndGuessTiles.make(answer: "elephant", language: .en, seed: seed)))
        })

        #expect(arrangements.count > 15)
    }

    @Test func tilesAreAnswerLettersPlusDecoys() {
        let tiles = DrawAndGuessTiles.make(answer: "Ice cream", language: .en, seed: "a")
        let tileCounts = counts(letters(tiles))
        let answerCounts = counts(Array("ICECREAM"))

        for (letter, count) in answerCounts {
            #expect(tileCounts[letter, default: 0] >= count)
        }
        #expect(!letters(tiles).contains(" "))
    }

    @Test func tileIdsAreUniquePositions() {
        let tiles = DrawAndGuessTiles.make(answer: "banana", language: .en, seed: "a")

        #expect(tiles.map(\.id) == Array(tiles.indices))
    }

    @Test(arguments: [
        (2, 6), (3, 12), (4, 12), (8, 12), (9, 18), (10, 18), (13, 18), (14, 18),
        (15, 18), (17, 18), (18, 24), (20, 24)
    ])
    func tileCountIsAMultipleOfSix(letterCount: Int, expected: Int) {
        #expect(DrawAndGuessTiles.tileCount(forLetterCount: letterCount) == expected)
        #expect(expected % 6 == 0)
        #expect(expected > letterCount)
    }

    @Test func shortWordGetsTwelveTiles() {
        #expect(DrawAndGuessTiles.make(answer: "dog", language: .en, seed: "a").count == 12)
        #expect(DrawAndGuessTiles.make(answer: "brunost", language: .nb, seed: "a").count == 12)
    }

    @Test func longAnswerFillsTheRowWithoutTheCap() {
        let answer = String(repeating: "a", count: 16)
        let tiles = DrawAndGuessTiles.make(answer: answer, language: .en, seed: "a")

        #expect(tiles.count == 18)
        #expect(letters(tiles).filter { $0 == "A" }.count >= 16)
    }

    @Test func tilesNeverSpellOnlyTheAnswer() {
        for length in 1...20 {
            let answer = String(repeating: "e", count: length)
            let tiles = DrawAndGuessTiles.make(answer: answer, language: .en, seed: "a")

            #expect(tiles.count > length)
        }
    }

    @Test func englishDecoysStayInTheEnglishAlphabet() {
        for seed in 0..<200 {
            let tiles = DrawAndGuessTiles.make(answer: "cat", language: .en, seed: "\(seed)")

            #expect(Set(letters(tiles)).isSubset(of: DrawAndGuessLanguage.en.alphabet))
            #expect(!letters(tiles).contains { "ÆØÅ".contains($0) })
        }
    }

    @Test func norwegianDecoysCanBeNorwegianLetters() {
        var seen: Set<Character> = []
        for seed in 0..<200 {
            let tiles = DrawAndGuessTiles.make(answer: "katt", language: .nb, seed: "\(seed)")
            seen.formUnion(letters(tiles))
            #expect(Set(letters(tiles)).isSubset(of: DrawAndGuessLanguage.nb.alphabet))
        }

        #expect(["Æ", "Ø", "Å"].allSatisfy(seen.contains))
        #expect(DrawAndGuessLanguage.nb.alphabet.isSuperset(of: DrawAndGuessLanguage.en.alphabet))
        #expect(DrawAndGuessLanguage.en.alphabet.count == 26)
        #expect(DrawAndGuessLanguage.nb.alphabet.count == 29)
    }

    @Test func norwegianAnswerLettersBecomeTiles() {
        let tiles = DrawAndGuessTiles.make(answer: "blåbærsyltetøy", language: .nb, seed: "a")
        let tileCounts = counts(letters(tiles))

        #expect(tileCounts["Å"] ?? 0 >= 1)
        #expect(tileCounts["Æ"] ?? 0 >= 1)
        #expect(tileCounts["Ø"] ?? 0 >= 1)
        #expect(tileCounts["B"] ?? 0 >= 2)
    }

    @Test func decoysFollowLetterFrequency() {
        var decoyCounts: [Character: Int] = [:]
        for seed in 0..<500 {
            let tiles = DrawAndGuessTiles.make(answer: "ab", language: .en, seed: "\(seed)")
            // "ab" gives 4 decoys. Count every non-answer tile.
            for letter in letters(tiles) where letter != "A" && letter != "B" {
                decoyCounts[letter, default: 0] += 1
            }
        }

        #expect(decoyCounts["E", default: 0] > 150)
        #expect(decoyCounts["Z", default: 0] < 20)
    }

    @Test func decoysAreDifferentLetters() {
        let tiles = DrawAndGuessTiles.make(answer: "ab", language: .en, seed: "a")
        let decoys = letters(tiles).filter { $0 != "A" && $0 != "B" }

        #expect(Set(decoys).count == decoys.count)
    }
}
