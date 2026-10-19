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

    // MARK: Loading

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
}
