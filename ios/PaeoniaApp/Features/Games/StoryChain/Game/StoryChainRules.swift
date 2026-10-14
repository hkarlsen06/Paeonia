import Foundation

/// The Story Chain rules the phone checks before it sends a move. They mirror
/// `backend/convex/lib/storyChain.ts`, which checks the same rules again on the
/// server, so change both sides together. Lengths count Unicode code points
/// (`unicodeScalars`), not the characters a person sees, so a family emoji
/// made of three people joined by two joiners counts as 5.
nonisolated enum StoryChainRules {
    /// A line is 2 to 240 code points after normalizing.
    static let minLineLength = 2
    static let maxLineLength = 240
    /// The composer shows its counter above this length.
    static let counterThreshold = 200
    /// The writer may make a line the last one from this line number on.
    static let endFromLine = 8
    /// The story always ends with this line number.
    static let maxLines = 20
    static let maxTitleLength = 40
    /// A dare word is one word of this many letters.
    static let dareWordLength = 2...20

    // MARK: Text

    /// Trims the text and turns every run of whitespace, line breaks included,
    /// into one space. So a line is always one run of prose.
    static func normalizeText(_ text: String) -> String {
        text.unicodeScalars
            .split(whereSeparator: { isWhitespace($0) })
            .map { String($0) }
            .joined(separator: " ")
    }

    /// The length that counts against the limits: code points of the normalized text.
    static func length(_ text: String) -> Int {
        normalizeText(text).unicodeScalars.count
    }

    static func isValidLine(_ text: String) -> Bool {
        let count = length(text)
        return count >= minLineLength && count <= maxLineLength
    }

    /// The title to send, or nil when it is empty or longer than 40 code points.
    static func normalizedTitle(_ title: String) -> String? {
        let normalized = normalizeText(title)
        guard !normalized.isEmpty, normalized.unicodeScalars.count <= maxTitleLength else {
            return nil
        }
        return normalized
    }

    /// The first `limit` code points of the text, untouched otherwise. For the
    /// live draft, which the reader shows as typed.
    static func truncated(_ text: String, to limit: Int = maxLineLength) -> String {
        String(text.unicodeScalars.prefix(limit))
    }

    // MARK: Dare word

    /// The dare word to send, or nil when it is not one word of 2 to 20 letters.
    /// Letters of any script count, so "café" and "smørbrød" work. The result is
    /// in NFC and lowercase.
    static func normalizedDareWord(_ word: String) -> String? {
        // `normalizeText` trims. It also squeezes inner spaces, but a space is not
        // a letter, so a text with inner spaces still fails the letter test below.
        let folded = normalizeText(word.precomposedStringWithCanonicalMapping)
            .lowercased()
            .precomposedStringWithCanonicalMapping
        let scalars = folded.unicodeScalars
        guard dareWordLength.contains(scalars.count), scalars.allSatisfy({ isLetter($0) }) else {
            return nil
        }
        return folded
    }

    /// Whether the line contains the dare word, ignoring case. "hunden" and
    /// "gårdshunden" both use "hund". Both sides are compared in NFC, so a word
    /// typed with a combining accent still matches.
    static func lineUses(_ line: String, dare: String) -> Bool {
        let haystack = Array(matchKey(line).unicodeScalars)
        let needle = Array(matchKey(dare).unicodeScalars)
        guard haystack.count >= needle.count else {
            return false
        }
        // An empty word is in every line, as `String.includes("")` is in JavaScript.
        return (0...(haystack.count - needle.count)).contains { start in
            haystack[start..<(start + needle.count)].elementsEqual(needle)
        }
    }

    // MARK: Ending

    /// The writer may make this line the last one.
    static func canEnd(lineNumber: Int) -> Bool {
        lineNumber >= endFromLine
    }

    /// This line is always the last one.
    static func mustEnd(lineNumber: Int) -> Bool {
        lineNumber >= maxLines
    }

    // MARK: Private

    private static func matchKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// The same set as `\s` in JavaScript, which the server uses.
    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            true
        default:
            false
        }
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            true
        default:
            false
        }
    }
}

/// What the composer knows about a draft: the text that would be sent and
/// whether it may be sent.
nonisolated struct StoryChainLineCheck: Equatable, Sendable {
    /// The draft after `StoryChainRules.normalizeText`. This is what goes out.
    let text: String
    /// Code points in `text`.
    let length: Int
    let isTooShort: Bool
    let isTooLong: Bool
    /// Whether the draft contains the dare word. Nil when there is no dare.
    let usesDare: Bool?

    init(draft: String, dare: String? = nil) {
        let normalized = StoryChainRules.normalizeText(draft)
        let count = normalized.unicodeScalars.count
        text = normalized
        length = count
        isTooShort = count < StoryChainRules.minLineLength
        isTooLong = count > StoryChainRules.maxLineLength
        usesDare = dare.map { StoryChainRules.lineUses(normalized, dare: $0) }
    }

    var canSend: Bool {
        !isTooShort && !isTooLong && usesDare != false
    }

    /// The counter shows from 200 code points on.
    var showsCounter: Bool {
        length > StoryChainRules.counterThreshold
    }
}
