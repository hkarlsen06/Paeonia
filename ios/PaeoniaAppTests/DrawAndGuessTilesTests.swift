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

    @Test func tilesAreAnswerLettersPlusDecoys() {
        let tiles = DrawAndGuessTiles.make(answer: "Ice cream", language: .en, seed: "a")
        let tileCounts = counts(letters(tiles))
        let answerCounts = counts(Array("ICECREAM"))

        for (letter, count) in answerCounts {
            #expect(tileCounts[letter, default: 0] >= count)
        }
        #expect(!letters(tiles).contains(" "))
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

    @Test func norwegianAnswerLettersBecomeTiles() {
        let tiles = DrawAndGuessTiles.make(answer: "blåbærsyltetøy", language: .nb, seed: "a")
        let tileCounts = counts(letters(tiles))

        #expect(tileCounts["Å"] ?? 0 >= 1)
        #expect(tileCounts["Æ"] ?? 0 >= 1)
        #expect(tileCounts["Ø"] ?? 0 >= 1)
        #expect(tileCounts["B"] ?? 0 >= 2)
    }
}
