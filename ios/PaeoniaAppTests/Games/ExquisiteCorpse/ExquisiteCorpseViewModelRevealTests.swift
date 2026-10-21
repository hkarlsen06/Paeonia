import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// The reveal of a finished figure, and moving past it. The viewer is `me`.
/// Figure 1 starts with the partner, who draws its head and legs, and `me` draws
/// the body. Figure 2 starts with `me`.
@MainActor
struct ExquisiteCorpseViewModelRevealTests {
    private typealias Fixture = ExquisiteCorpseFixture

    /// The state of an unseen figure, with the drawings on the phone and ready to download.
    private func reveal(of number: Int) -> (env: ExquisiteCorpseTestEnvironment, figure: RemoteExquisiteCorpseFigure) {
        let state = Fixture.unseenReveal(figure: number)
        let env = ExquisiteCorpseTestEnvironment(state: state)
        env.seedDrawings(of: state.recentFigures[0])
        return (env, state.recentFigures[0])
    }

    @Test func theRevealWaitsForADrawingThatIsStillOnItsWay() async throws {
        let (env, figure) = reveal(of: 1)
        let legsID = try #require(figure.parts[2].drawingMediaAssetID)
        env.transfer.removeFile(for: legsID)
        let viewModel = env.viewModel()
        await viewModel.reload()

        let failed = await waitUntil { viewModel.revealLoadFailed }
        #expect(failed)
        #expect(viewModel.revealContent?.isReady == false)
        // The two drawings that did arrive are in the content already.
        let headLoaded = await waitUntil { viewModel.revealContent?.part(.head)?.drawing != nil }
        #expect(headLoaded)
        #expect(viewModel.revealContent?.part(.body)?.drawing != nil)
        #expect(viewModel.revealContent?.part(.legs)?.drawing == nil)

        env.transfer.setFile(CorpseDrawings.part(2).dataRepresentation(), for: legsID)
        viewModel.retryLoadingReveal()
        let ready = await waitUntil { viewModel.revealContent?.isReady == true }

        #expect(ready)
        #expect(!viewModel.revealLoadFailed)
    }

    @Test func continueQueuesOneRevealSeenAndLeavesTheRevealAtOnce() async throws {
        let (env, figure) = reveal(of: 1)
        let viewModel = env.viewModel()
        await viewModel.reload()
        let ready = await waitUntil { viewModel.revealContent?.isReady == true }
        #expect(ready)

        await viewModel.continueFromReveal()
        await viewModel.continueFromReveal()

        let marks = await env.queued(.exquisiteCorpseRevealSeen)
        #expect(marks.count == 1)
        let payload = try JSONDecoder().decode(
            ExquisiteCorpseRevealSeenPayload.self,
            from: try #require(marks.first?.requestData)
        )
        #expect(payload.figureID == figure.id)
        #expect(marks.first?.idempotencyScope == "exquisite-corpse-reveal-seen:\(figure.id.uuidString.lowercased())")
        // The next head is mine, and the screen goes straight to it.
        #expect(viewModel.phase == .drawing)
        #expect(viewModel.part == .head)
        #expect(viewModel.figureNumber == 2)
        #expect(viewModel.revealContent == nil)
        #expect(env.room.role == .drawing)
    }

    @Test func theRevealStaysGoneOnceTheServerHasTheMark() async {
        let (env, _) = reveal(of: 1)
        let viewModel = env.viewModel()
        await viewModel.reload()
        await viewModel.continueFromReveal()

        // The server saw the mark: it sends the figure back as seen.
        var seen = Fixture.unseenReveal(figure: 1)
        let figure = seen.recentFigures[0]
        seen.recentFigures = [RemoteExquisiteCorpseFigure(
            id: figure.id,
            number: figure.number,
            starterUserID: figure.starterUserID,
            createdAt: figure.createdAt,
            finishedAt: figure.finishedAt,
            myRevealSeenAt: Fixture.now,
            parts: figure.parts
        )]
        let queued = await env.queued(.exquisiteCorpseRevealSeen)
        for operation in queued {
            try? await env.pending.markSucceeded(clientOperationID: operation.operation.id, at: Fixture.now)
        }
        await env.serverState(seen)
        await viewModel.reload()

        #expect(viewModel.phase == .drawing)
    }
}
