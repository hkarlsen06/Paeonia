import Foundation
import SwiftUI

/// What the person typed, as words to look for. The phone and the server split a search the same way.
nonisolated struct SearchQuery: Equatable, Sendable {
    /// The most words one search uses.
    static let maxWords = 6
    /// Fewer letters than this finds nothing, because one letter matches almost everything.
    static let minLetters = 2

    let text: String
    /// Lowercased words, without repeats.
    let words: [String]

    init(_ text: String) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        let words = self.text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        self.words = Array(words.prefix(Self.maxWords))
    }

    var isSearchable: Bool {
        words.reduce(0) { $0 + $1.count } >= Self.minLetters
    }
}

/// Case and accent insensitive matching, and the snippet around a match.
nonisolated enum SearchText {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Every word appears in the text, also inside another word, so "ferie" finds "sommerferie".
    static func containsEveryWord(_ words: [String], in text: String) -> Bool {
        words.allSatisfy { text.range(of: $0, options: options) != nil }
    }

    /// The text around the first matched word, cut at word breaks, with "…" where it was cut.
    /// Whitespace is collapsed. Text that fits is returned whole.
    static func snippet(of text: String, words: [String], maxLength: Int = 140) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > maxLength else { return flat }

        let firstMatch = words
            .compactMap { flat.range(of: $0, options: options)?.lowerBound }
            .min() ?? flat.startIndex
        let matchOffset = flat.distance(from: flat.startIndex, to: firstMatch)

        // A little lead-in before the match, then start on a whole word.
        let start = max(0, matchOffset - maxLength / 4)
        let end = min(flat.count, start + maxLength)
        var startIndex = flat.index(flat.startIndex, offsetBy: start)
        var endIndex = flat.index(flat.startIndex, offsetBy: end)
        if start > 0, let space = flat[startIndex..<firstMatch].firstIndex(of: " ") {
            startIndex = flat.index(after: space)
        }
        if end < flat.count, let space = flat[firstMatch..<endIndex].lastIndex(of: " ") {
            endIndex = space
        }
        let cutBefore = startIndex > flat.startIndex
        let cutAfter = endIndex < flat.endIndex
        return (cutBefore ? "…" : "") + String(flat[startIndex..<endIndex]) + (cutAfter ? "…" : "")
    }

    /// `text` with every matched word marked, for a row's line.
    static func highlighted(_ text: String, words: [String]) -> AttributedString {
        var attributed = AttributedString(text)
        for word in words {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(of: word, options: options, range: searchStart..<text.endIndex) {
                if let lower = AttributedString.Index(range.lowerBound, within: attributed),
                   let upper = AttributedString.Index(range.upperBound, within: attributed) {
                    attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
                    attributed[lower..<upper].foregroundColor = .paeoniaAccentPrimary
                }
                searchStart = range.upperBound
            }
        }
        return attributed
    }
}
