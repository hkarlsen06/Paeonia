import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// One creature from "Our creatures": loading its three drawings, the credits, the
/// replay and the star.
@MainActor
struct ExquisiteCorpseHistoryDetailTests {
    private typealias Fixture = ExquisiteCorpseFixture

    private let environment = ExquisiteCorpseTestEnvironment(state: nil)
    /// Figure 2 starts with `me`, so `me` drew its head and legs and the partner its body.
    private let figure = Fixture.figure(2, revealSeen: true)

    private func makeDetail() -> ExquisiteCorpseHistoryDetailViewModel {
        let dependencies = environment.dependencies(withRoom: false)
        let stars = GameStars(source: .exquisiteCorpse(cache: environment.cache), dependencies: dependencies) {
            Fixture.me
        }
        return ExquisiteCorpseHistoryDetailViewModel(
            figure: figure,
            participants: ExquisiteCorpseTestEnvironment.participants,
            stars: stars,
            drawings: GameHistoryDrawings(store: environment.drawingStore, transfer: environment.transfer)
        )
    }

    private func assetID(_ partIndex: Int) throws -> UUID {
        try #require(figure.part(at: partIndex)?.drawingMediaAssetID)
    }

    /// Puts the file of a part on the phone.
    private func keep(_ partIndex: Int) throws {
        environment.drawingStore.saveDownloadedDrawing(
            CorpseDrawings.part(partIndex).dataRepresentation(),
            mediaAssetID: try assetID(partIndex)
        )
    }

    private func keepAll() throws {
        for index in 0..<ExquisiteCorpsePartKind.allCases.count {
            try keep(index)
        }
    }

    // MARK: Loading

    @Test func theCreditsShowBeforeTheDrawingsHaveLoaded() {
        let detail = makeDetail()

        #expect(detail.drawingState == .loading)
        #expect(!detail.content.isReady)
        #expect(detail.content.number == 2)
        #expect(detail.content.parts.map(\.drawerIsMe) == [true, false, true])
    }

    @Test func allThreeDrawingsLoadAndTheFoldsOpen() async throws {
        let detail = makeDetail()
        try keepAll()

        await detail.load(showsAtOnce: false)

        #expect(detail.drawingState == .ready)
        #expect(detail.content.isReady)
        #expect(detail.timeline.hasBegun)
        #expect(!detail.timeline.isSettled)
        detail.stop()
    }

    @Test func aMissingDrawingFailsAndTryAgainLoadsIt() async throws {
        let detail = makeDetail()
        try keep(0)
        try keep(1)

        await detail.load(showsAtOnce: false)
        #expect(detail.drawingState == .failed)
        #expect(!detail.timeline.hasBegun)

        // The legs can be downloaded now.
        environment.transfer.setFile(CorpseDrawings.part(2).dataRepresentation(), for: try assetID(2))
        await detail.retryLoading(showsAtOnce: false)

        #expect(detail.drawingState == .ready)
        detail.stop()
    }

    @Test func aDrawingThatIsNotOnThePhoneIsDownloadedAndKept() async throws {
        let detail = makeDetail()
        try keep(0)
        try keep(2)
        let partnersBody = try assetID(1)
        environment.transfer.setFile(CorpseDrawings.part(1).dataRepresentation(), for: partnersBody)

        await detail.load(showsAtOnce: true)

        #expect(detail.drawingState == .ready)
        #expect(environment.transfer.downloads == [partnersBody])
        #expect(environment.drawingStore.downloadedDrawing(mediaAssetID: partnersBody) != nil)
    }

    // MARK: Replay

    @Test func reduceMotionShowsTheWholeCreatureAndPlayAgainReplaysTheStrokes() async throws {
        let detail = makeDetail()
        try keepAll()

        await detail.load(showsAtOnce: true)

        #expect(detail.drawingState == .ready)
        #expect(detail.timeline.isSettled)
        #expect(!detail.player.isPlaying)

        detail.replay()

        #expect(detail.player.playingPart == .head)
        #expect(detail.timeline.isSettled)
    }

    @Test func playAgainClosesTheFoldsAndOpensThemAgain() async throws {
        let detail = makeDetail()
        try keepAll()
        await detail.load(showsAtOnce: false)
        detail.showWholeFigure()
        #expect(detail.timeline.isSettled)

        detail.replay()

        #expect(!detail.timeline.isSettled)
        #expect(detail.timeline.openParts.isEmpty)
        #expect(detail.timeline.hasBegun)
        detail.stop()
    }

    @Test func aTapShowsTheWholeCreatureAtOnce() async throws {
        let detail = makeDetail()
        try keepAll()
        await detail.load(showsAtOnce: false)

        detail.showWholeFigure()

        #expect(detail.timeline.isSettled)
        #expect(detail.timeline.openParts == Set(ExquisiteCorpsePartKind.allCases))
        #expect(!detail.player.isPlaying)
    }

    @Test func aFoldThatOpensStartsItsStrokes() async throws {
        let detail = makeDetail()
        try keepAll()
        await detail.load(showsAtOnce: false)

        detail.timelineStageChanged(to: .playing(.body))

        #expect(detail.player.playingPart == .body)
        detail.stop()
    }

    @Test func playAgainDoesNothingBeforeTheDrawingsAreReady() {
        let detail = makeDetail()

        detail.replay()
        detail.showWholeFigure()

        #expect(!detail.timeline.hasBegun)
        #expect(!detail.player.isPlaying)
    }

    // MARK: Star

    @Test func theStarToggleIsMineAndShowsAtOnce() async {
        let detail = makeDetail()
        #expect(!detail.isStarred)

        await detail.toggleStar()
        #expect(detail.isStarred)
        let queued = await environment.queued(.exquisiteCorpseStar)
        #expect(queued.count == 1)

        await detail.toggleStar()
        #expect(!detail.isStarred)
    }

    @Test func theDateIsTheDayTheCreatureWasFinished() throws {
        let detail = makeDetail()
        let finished = try #require(figure.finishedAt)

        #expect(detail.dateText == finished.formatted(date: .abbreviated, time: .omitted))
    }
}
