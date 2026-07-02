import Testing
@testable import PaeoniaApp

/// Covers the pure pre-auth welcome carousel: the number and order of screens, and the
/// "last screen leads to sign-in" rule.
struct WelcomeCarouselTests {
    @Test func standardHasThreeScreensInOrder() {
        let carousel = WelcomeCarousel.standard

        #expect(carousel.pages.map(\.kind) == [.doodle, .dailyQuestions, .countdown])
        #expect(carousel.count == 3)
    }

    @Test func isLastOnlyForTheFinalIndex() {
        let carousel = WelcomeCarousel.standard

        #expect(carousel.isLast(carousel.lastIndex))
        #expect(carousel.isLast(2))
        #expect(!carousel.isLast(0))
        #expect(!carousel.isLast(1))
    }

    @Test func pageLookupIsBoundsSafe() {
        let carousel = WelcomeCarousel.standard

        #expect(carousel.page(at: 0)?.kind == .doodle)
        #expect(carousel.page(at: -1) == nil)
        #expect(carousel.page(at: 99) == nil)
    }
}
