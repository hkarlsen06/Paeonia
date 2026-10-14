import Foundation

/// Cuts a line into the words the arrival animation writes in one by one.
nonisolated enum StoryChainWords {
    /// The character ranges of the words. Each range keeps the whitespace that
    /// follows its word, so the ranges together cover the whole text. Whitespace
    /// before the first word belongs to the first range.
    static func ranges(in characters: [Character]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        var seenWord = false
        var inTrailingSpace = false
        for (index, character) in characters.enumerated() {
            if character.isWhitespace {
                inTrailingSpace = seenWord
            } else {
                if inTrailingSpace {
                    ranges.append(start..<index)
                    start = index
                    inTrailingSpace = false
                }
                seenWord = true
            }
        }
        if start < characters.count {
            ranges.append(start..<characters.count)
        }
        return ranges
    }

    /// How many words the text has.
    static func count(in text: String) -> Int {
        ranges(in: Array(text)).count
    }
}

/// Finds the dared word inside the line that used it.
nonisolated enum StoryChainDareRange {
    /// The first place the word appears in the text, ignoring case. A word inside
    /// a longer word counts, as in the dare check: "hund" is in "gårdshund".
    static func range(of word: String, in text: String) -> Range<String.Index>? {
        guard !word.isEmpty else { return nil }
        return text.range(of: word, options: [.caseInsensitive])
    }

    /// The same place, counted in characters from the start of the text.
    static func characterRange(of word: String?, in text: String) -> Range<Int>? {
        guard let word, let match = range(of: word, in: text) else { return nil }
        let lower = text.distance(from: text.startIndex, to: match.lowerBound)
        let upper = text.distance(from: text.startIndex, to: match.upperBound)
        return lower..<upper
    }
}
