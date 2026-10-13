import CoreGraphics
import Testing
@testable import PaeoniaApp

struct DrawAndGuessSlotSizingTests {
    private func layout(_ lengths: [Int], width: CGFloat) -> DrawAndGuessSlotSizing.Layout {
        DrawAndGuessSlotSizing.layout(wordLengths: lengths, availableWidth: width, gap: 4, wordSpacing: 16)
    }

    private func pieceWidth(_ letters: Int, _ slot: CGFloat) -> CGFloat {
        CGFloat(letters) * slot + CGFloat(letters - 1) * 4
    }

    @Test func aShortWordFillsOneLineUpToTheWidestSlot() {
        #expect(layout([5], width: 370) == .init(slotWidth: 44, pieces: [5]))
        #expect(layout([8], width: 370) == .init(slotWidth: 42, pieces: [8]))
    }

    @Test func aWordTooWideForTheScreenSplitsEvenlyAndFits() {
        let result = layout([20], width: 343)

        #expect(result.pieces == [10, 10])
        #expect(result.slotWidth >= DrawAndGuessSlotSizing.minWidth)
        #expect(pieceWidth(10, result.slotWidth) <= 343)
    }

    @Test func wordsWrapWholeBeforeTheSlotsGetSmaller() {
        // ICE CREAM SUNDAE: "ice cream" on one line, "sundae" on the next.
        let result = layout([3, 5, 6], width: 343)

        #expect(result.pieces == [3, 5, 6])
        #expect(pieceWidth(3, result.slotWidth) + 16 + pieceWidth(5, result.slotWidth) <= 343)
        #expect(result.slotWidth > DrawAndGuessSlotSizing.minWidth)
    }

    @Test func splitMakesTheFewestEvenPieces() {
        #expect(DrawAndGuessSlotSizing.split(20, maxCount: 9) == [7, 7, 6])
        #expect(DrawAndGuessSlotSizing.split(8, maxCount: 10) == [8])
    }
}
