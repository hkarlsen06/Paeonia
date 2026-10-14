import SwiftUI

/// Marks a piece of the paragraph with the line and word it belongs to. The
/// renderer reads it back to write a line in word by word and to find where each
/// line sits for taps.
nonisolated struct StoryChainLineTag: TextAttribute {
    let lineID: UUID
    let wordIndex: Int
    let wordCount: Int
}

/// Marks the caret after the partner's draft, so the renderer can blink it.
nonisolated struct StoryChainCaretTag: TextAttribute {}

/// One piece of the paragraph with one style. A word that holds the dared word
/// splits into up to three pieces, and all of them carry the same tag.
struct StoryChainParagraphSegment: Equatable {
    enum Role: Equatable {
        case opening
        case mine
        case partner
        case ghost
        case caret
    }

    var string: String
    var role: Role
    /// The line this piece belongs to. Nil for the opening, the draft and the caret.
    var lineID: UUID?
    var wordIndex = 0
    var wordCount = 0
    var isDared = false
}

/// Builds the story as one flowing paragraph: the opening, then every line with a
/// space after it, then the partner's draft and its caret.
enum StoryChainParagraph {
    /// The caret is a thin vertical bar. The renderer draws it with a blinking opacity.
    static let caret = "|"

    /// The pieces of the paragraph in reading order.
    static func segments(for content: StoryChainPageContent) -> [StoryChainParagraphSegment] {
        var result: [StoryChainParagraphSegment] = []
        if let opening = content.opening, !opening.isEmpty {
            result.append(StoryChainParagraphSegment(string: opening + " ", role: .opening))
        }
        for line in content.lines {
            result.append(contentsOf: segments(for: line))
        }
        if let ghost = content.ghost {
            if !ghost.text.isEmpty {
                result.append(StoryChainParagraphSegment(string: flattened(ghost.text), role: .ghost))
            }
            result.append(StoryChainParagraphSegment(string: caret, role: .caret))
        }
        return result
    }

    /// The pieces of one line. Its last word keeps the space that follows the line.
    static func segments(for line: StoryChainPageLine) -> [StoryChainParagraphSegment] {
        let characters = Array(line.text + " ")
        let words = StoryChainWords.ranges(in: characters)
        let dared = StoryChainDareRange.characterRange(of: line.usedDare, in: line.text)
        var result: [StoryChainParagraphSegment] = []
        for (index, word) in words.enumerated() {
            for piece in pieces(of: word, dared: dared) {
                result.append(StoryChainParagraphSegment(
                    string: String(characters[piece.range]),
                    role: line.isMine ? .mine : .partner,
                    lineID: line.id,
                    wordIndex: index,
                    wordCount: words.count,
                    isDared: piece.isDared
                ))
            }
        }
        return result
    }

    /// Cuts a word where the dared range starts and ends.
    static func pieces(of word: Range<Int>, dared: Range<Int>?) -> [(range: Range<Int>, isDared: Bool)] {
        guard let dared else { return [(word, false)] }
        let lower = min(max(dared.lowerBound, word.lowerBound), word.upperBound)
        let upper = min(max(dared.upperBound, word.lowerBound), word.upperBound)
        guard lower < upper else { return [(word, false)] }
        var result: [(range: Range<Int>, isDared: Bool)] = []
        if word.lowerBound < lower { result.append((word.lowerBound..<lower, false)) }
        result.append((lower..<upper, true))
        if upper < word.upperBound { result.append((upper..<word.upperBound, false)) }
        return result
    }

    /// Line breaks in a draft become spaces, so the draft keeps flowing in the paragraph.
    static func flattened(_ draft: String) -> String {
        String(draft.map { $0.isNewline ? " " : $0 })
    }

    /// The most pieces one interpolation joins. Formatting a string with about
    /// 150 or more arguments overflows, and the whole paragraph then draws
    /// nothing, so longer stories are joined in groups.
    static let piecesPerJoin = 64

    /// The paragraph as one `Text`. SwiftUI joins the pieces through string
    /// interpolation, which keeps each piece's style and tag. Text addition
    /// (`+`) is deprecated.
    static func text(from segments: [StoryChainParagraphSegment]) -> Text {
        guard !segments.isEmpty else { return Text(verbatim: "") }
        return joined(segments.map(\.styledText))
    }

    /// Joins texts in groups of at most `piecesPerJoin`, then joins the groups
    /// the same way, so no single interpolation holds too many arguments.
    static func joined(_ texts: [Text]) -> Text {
        guard texts.count > piecesPerJoin else { return interpolated(texts) }
        let groups = stride(from: 0, to: texts.count, by: piecesPerJoin).map { start in
            interpolated(Array(texts[start..<min(start + piecesPerJoin, texts.count)]))
        }
        return joined(groups)
    }

    private static func interpolated(_ texts: [Text]) -> Text {
        var interpolation = LocalizedStringKey.StringInterpolation(literalCapacity: 0, interpolationCount: texts.count)
        for text in texts {
            interpolation.appendInterpolation(text)
        }
        return Text(LocalizedStringKey(stringInterpolation: interpolation))
    }

    static func text(for content: StoryChainPageContent) -> Text {
        text(from: segments(for: content))
    }
}

extension StoryChainParagraphSegment {
    var ink: Color {
        switch role {
        case .opening: .paeoniaTextSecondary
        case .mine: StoryChainPageStyle.mineInk
        case .partner, .caret: StoryChainPageStyle.partnerInk
        case .ghost: StoryChainPageStyle.partnerInk.opacity(StoryChainPageStyle.ghostOpacity)
        }
    }

    var styledText: Text {
        var text = Text(verbatim: string).foregroundStyle(ink)
        if role == .opening {
            text = text.italic()
        }
        if isDared {
            text = text.underline(true, pattern: .solid, color: Color.paeoniaInkGold)
        }
        if let lineID {
            text = text.customAttribute(StoryChainLineTag(lineID: lineID, wordIndex: wordIndex, wordCount: wordCount))
        }
        if role == .caret {
            text = text.customAttribute(StoryChainCaretTag())
        }
        return text
    }
}
