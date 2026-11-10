import Foundation

/// The rule for a countdown title and a list item title, the same one `requireTitle` in
/// `backend/convex/lib/text.ts` checks: the text trimmed of white space, then at most a
/// number of Unicode code points, so an emoji made of eight code points counts as eight.
nonisolated enum ShortTitle {
    /// Everything JavaScript's `trim()` removes, so the server finds nothing left to trim.
    private static let whiteSpace = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))

    /// The text the server stores for `text`: trimmed, and cut to `maxCodePoints` without
    /// splitting a character. Empty when nothing is left.
    static func normalized(_ text: String, maxCodePoints: Int) -> String {
        MemoryDataService.prefix(text.trimmingCharacters(in: whiteSpace), fittingCodePoints: maxCodePoints)
            .trimmingCharacters(in: whiteSpace)
    }
}
