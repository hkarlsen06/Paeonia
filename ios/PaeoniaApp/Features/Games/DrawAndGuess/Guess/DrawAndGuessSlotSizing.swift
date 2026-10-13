import CoreGraphics

/// How wide the answer slots are and where the words break, so every slot stays
/// on screen. Words never split unless one is wider than the line at the smallest
/// slot. Such a word splits into even pieces.
nonisolated enum DrawAndGuessSlotSizing {
    struct Layout: Equatable {
        let slotWidth: CGFloat
        /// Letters per piece, in order. A piece is a word, or part of a long word.
        let pieces: [Int]
    }

    static let minWidth: CGFloat = 28
    static let maxWidth: CGFloat = 44

    /// - Parameters:
    ///   - gap: The space between two slots of a word.
    ///   - wordSpacing: The space between two pieces on one line.
    static func layout(wordLengths: [Int], availableWidth: CGFloat, gap: CGFloat, wordSpacing: CGFloat) -> Layout {
        let perLine = max(1, Int((availableWidth + gap) / (minWidth + gap)))
        let pieces = wordLengths.filter { $0 > 0 }.flatMap { split($0, maxCount: perLine) }
        func pieceWidth(_ letters: Int, _ width: CGFloat) -> CGFloat {
            CGFloat(letters) * width + CGFloat(max(0, letters - 1)) * gap
        }
        func lineCount(_ width: CGFloat) -> Int {
            var lines = 0
            var used: CGFloat = 0
            for piece in pieces {
                let needed = pieceWidth(piece, width)
                if lines == 0 || used + wordSpacing + needed > availableWidth {
                    lines += 1
                    used = needed
                } else {
                    used += wordSpacing + needed
                }
            }
            return lines
        }
        let fewestLines = lineCount(minWidth)
        var width = maxWidth
        // The widest slot that keeps every piece on screen and adds no line.
        while width > minWidth,
              pieces.contains(where: { pieceWidth($0, width) > availableWidth }) || lineCount(width) > fewestLines {
            width -= 1
        }
        return Layout(slotWidth: width, pieces: pieces)
    }

    /// Splits a word of `count` letters into the fewest even pieces of at most `maxCount`.
    static func split(_ count: Int, maxCount: Int) -> [Int] {
        let parts = (count + max(1, maxCount) - 1) / max(1, maxCount)
        guard parts > 1 else { return [count] }
        let base = count / parts
        let extra = count % parts
        return (0..<parts).map { $0 < extra ? base + 1 : base }
    }
}
