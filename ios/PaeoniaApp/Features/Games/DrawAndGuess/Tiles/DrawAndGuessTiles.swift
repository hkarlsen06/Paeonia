import Foundation

/// One letter tile. The id is its position in the set, so two tiles with the
/// same letter stay different.
nonisolated struct DrawAndGuessTile: Identifiable, Hashable, Sendable {
    let id: Int
    let letter: Character
}

/// The tiles under the answer slots: the answer's letters plus decoys, in
/// alphabetical order so a letter is quick to find. Both phones get the same
/// tiles for the same answer, language, and seed.
nonisolated enum DrawAndGuessTiles {
    static let rowSize = 6
    static let maxShortWordTiles = 18
    static let shortWordLetterLimit = 14
    static let decoysForShortWord = 4

    /// - Parameter seed: The round id.
    static func make(answer: String, language: DrawAndGuessLanguage, seed: String) -> [DrawAndGuessTile] {
        let letters = DrawAndGuessAnswer.letters(of: answer)
        var generator = DrawAndGuessSeededGenerator(seed: seed)
        let decoyCount = tileCount(forLetterCount: letters.count) - letters.count
        let letterPool = (letters + decoys(count: decoyCount, language: language, using: &generator))
            .sorted { alphabeticalPlace($0) < alphabeticalPlace($1) }
        return letterPool.enumerated().map { DrawAndGuessTile(id: $0.offset, letter: $0.element) }
    }

    /// A to Z, then Æ, Ø and Å, as the Norwegian alphabet ends.
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZÆØÅ")

    private static func alphabeticalPlace(_ letter: Character) -> Int {
        alphabet.firstIndex(of: letter) ?? alphabet.count
    }

    /// The smallest multiple of 6 that is at least letters + 4, capped at 18.
    /// Over 14 letters there is no cap: the smallest multiple of 6 that leaves
    /// at least one decoy, so the tiles never spell out the answer alone.
    static func tileCount(forLetterCount count: Int) -> Int {
        if count > shortWordLetterLimit {
            return roundedUpToRow(count + 1)
        }
        return min(maxShortWordTiles, roundedUpToRow(count + decoysForShortWord))
    }

    private static func roundedUpToRow(_ count: Int) -> Int {
        (count + rowSize - 1) / rowSize * rowSize
    }

    /// Different letters drawn by language frequency, each letter at most once.
    private static func decoys(
        count: Int,
        language: DrawAndGuessLanguage,
        using generator: inout DrawAndGuessSeededGenerator
    ) -> [Character] {
        var pool = language.decoyWeights
        var decoys: [Character] = []
        while decoys.count < count, !pool.isEmpty {
            var roll = generator.nextUnit() * pool.reduce(0) { $0 + $1.weight }
            let index = pool.firstIndex { entry in
                roll -= entry.weight
                return roll < 0
            } ?? pool.count - 1
            decoys.append(pool.remove(at: index).letter)
        }
        return decoys
    }
}
