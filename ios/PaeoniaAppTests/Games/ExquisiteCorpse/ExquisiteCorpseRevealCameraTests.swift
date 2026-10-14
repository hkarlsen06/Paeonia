import CoreGraphics
import Testing
@testable import PaeoniaApp

@MainActor
struct ExquisiteCorpseRevealCameraTests {
    private typealias Camera = ExquisiteCorpseRevealCamera

    /// A phone: a stage of 360 by 600 on a screen 700 high. The whole figure takes the top 600.
    private let phone = Camera(
        stage: CGSize(width: 360, height: 600),
        overviewHeight: 600,
        viewportHeight: 700,
        captionHeight: 72
    )

    private func camera(
        stage: CGSize,
        overview: CGFloat? = nil,
        viewport: CGFloat? = nil,
        caption: CGFloat = 72
    ) -> Camera {
        Camera(
            stage: stage,
            overviewHeight: overview ?? stage.height,
            viewportHeight: viewport ?? stage.height,
            captionHeight: caption
        )
    }

    private func isClose(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    // MARK: Sizes

    @Test func theWholeFigureFitsTheSmallerOfTheWidthAndAThirdOfTheHeight() {
        #expect(isClose(phone.fitSide, (600 - 16) / 3))

        let narrow = camera(stage: CGSize(width: 120, height: 900))
        #expect(isClose(narrow.fitSide, 120))
    }

    @Test func aPlayingPartTakesTheWidthWhenThatIsLessThanFiftyFivePercentOfTheHeight() {
        // 55% of 700 is 385, and the stage is 360 wide.
        #expect(isClose(phone.layoutSide, 360))
    }

    @Test func aPlayingPartTakesFiftyFivePercentOfTheHeightOnAWideStage() {
        let ipad = camera(stage: CGSize(width: 900, height: 900), viewport: 800)
        #expect(isClose(ipad.layoutSide, 440))
    }

    @Test func aPlayingPartLeavesRoomForItsCaption() {
        let short = camera(stage: CGSize(width: 360, height: 400), viewport: 700)
        #expect(isClose(short.layoutSide, 400 - 72 - 16))
        #expect(short.captionZone >= 72)
    }

    @Test func thePlayingSideIsNeverSmallerThanTheWholeFigureSide() {
        // A stage so low that nothing is left for the caption.
        let squeezed = camera(stage: CGSize(width: 300, height: 120))
        #expect(squeezed.layoutSide >= squeezed.fitSide)
        #expect(squeezed.overviewScale <= 1)
    }

    // MARK: Shots

    @Test func theWholeFigureIsCenteredInTheStage() {
        let placement = phone.placement(for: .overview)

        #expect(isClose(placement.scale, phone.fitSide / phone.layoutSide))
        #expect(isClose(placement.origin.x, (360 - phone.fitSide) / 2))
        #expect(isClose(placement.origin.y, (600 - phone.fitSide * 3) / 2))
        #expect(phone.visibleHeight(for: .overview) == 600)
    }

    @Test func aFramedPartIsAtFullSizeAndCenteredWithItsCaption() {
        let placement = phone.placement(for: .framing(.head))

        #expect(placement.scale == 1)
        #expect(isClose(placement.origin.x, 0))
        // 600 high, with 72 for the caption and 360 for the part: 84 above the part.
        #expect(isClose(placement.origin.y, 84))
        #expect(isClose(phone.visibleHeight(for: .framing(.head)), 84 + 360))
        #expect(isClose(phone.captionZone, 600 - 444))
    }

    @Test func theNextPartSlidesIntoTheSamePlaceAndThePartsBeforeItMoveUp() {
        let head = phone.placement(for: .framing(.head))
        let body = phone.placement(for: .framing(.body))
        let legs = phone.placement(for: .framing(.legs))

        #expect(isClose(head.origin.y - body.origin.y, phone.layoutSide))
        #expect(isClose(body.origin.y - legs.origin.y, phone.layoutSide))
        // The top of the framed part is where the figure's top would be minus the parts before it.
        #expect(isClose(body.origin.y + phone.layoutSide, head.origin.y))
    }

    @Test func theTextUnderTheFigureLeavesTheFramedPartInTheMiddleOfTheScreen() {
        // The stage is 900 high because of the text, but the screen is 700 high. The whole
        // figure fits above the text, in 600, and a framed part sits in the middle of 700.
        let scrolling = camera(stage: CGSize(width: 360, height: 900), overview: 600, viewport: 700)

        #expect(isClose(scrolling.fitSide, (600 - 16) / 3))
        #expect(isClose(scrolling.placement(for: .overview).origin.y, (600 - scrolling.fitSide * 3) / 2))
        #expect(isClose(scrolling.placement(for: .framing(.head)).origin.y, (700 - 72 - 360) / 2))
        #expect(isClose(scrolling.captionTop + scrolling.captionZone, 700))
    }

    @Test func aFramedPartHidesWhatComesAfterIt() {
        for part in ExquisiteCorpsePartKind.allCases {
            #expect(phone.visibleHeight(for: .framing(part)) < phone.stage.height)
        }
    }

    // MARK: Lines

    @Test func theLinesBetweenPartsAreTwoPointsWhenTheWholeFigureShows() {
        #expect(isClose(phone.hairline * phone.overviewScale, 2))
    }
}
