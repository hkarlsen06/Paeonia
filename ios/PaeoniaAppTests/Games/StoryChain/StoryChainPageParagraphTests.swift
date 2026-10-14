import SwiftUI
import Testing
@testable import PaeoniaApp

/// The story paragraph is one `Text` joined from a piece per word. A long story
/// has hundreds of pieces, which one string interpolation can't format.
@MainActor
struct StoryChainPageParagraphTests {
    private func content(lines count: Int) -> StoryChainPageContent {
        let lines = (1...count).map { number in
            StoryChainPageLine(
                id: UUID(),
                number: number,
                text: "Line \(number) is a sentence with about ten short words, and then a few more after it.",
                isMine: number.isMultiple(of: 2),
                usedDare: nil,
                authorName: "Robin",
                createdAt: .now
            )
        }
        return StoryChainPageContent(opening: "The key had been taped under the bench for years.", lines: lines)
    }

    private func height(of content: StoryChainPageContent) -> CGFloat {
        let view = StoryChainParagraph.text(for: content)
            .font(StoryChainPageStyle.bodyFont)
            .frame(width: 320)
            .fixedSize(horizontal: false, vertical: true)
        return ImageRenderer(content: view).uiImage?.size.height ?? 0
    }

    @Test func aStoryOfTwentyLinesDrawsEveryLine() {
        let short = height(of: content(lines: 1))
        let long = height(of: content(lines: 20))

        #expect(StoryChainParagraph.segments(for: content(lines: 20)).count > StoryChainParagraph.piecesPerJoin * 2)
        #expect(short > 0)
        #expect(long > short * 10)
    }
}
