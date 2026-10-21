import Foundation
import Testing
@testable import PaeoniaApp

/// What the screen shows while parts wait on this phone. The viewer is `me`.
/// Figure 1 starts with the partner and figure 2 with `me`.
struct ExquisiteCorpseQueuedPartTests {
    private typealias Fixture = ExquisiteCorpseFixture

    private func resolve(
        _ state: RemoteExquisiteCorpseState?,
        pending: ExquisiteCorpsePendingWork = .none,
        live: Bool = false
    ) -> ExquisiteCorpseResolution {
        Fixture.resolver.resolve(state: state, hasSettings: true, pending: pending, isPartnerDrawingLive: live)
    }

    @Test func aQueuedHeadPassesTheTurnAndPutsThePartInTheFigure() {
        let idea = Fixture.idea("a grandma")
        let queued = Fixture.queuedPart(figure: 2, partIndex: 0, idea: idea)
        let state = Fixture.state(game: Fixture.game(figure: 2, partIndex: 0, turn: Fixture.me))

        let resolution = resolve(state, pending: Fixture.pending(parts: [queued]))

        #expect(resolution.phase == .waiting)
        #expect(resolution.turnPhase == .waiting)
        #expect(resolution.part == .body)
        #expect(resolution.isWaitingToSend)
        let figure = resolution.figure
        #expect(figure?.id == queued.figureID)
        #expect(figure?.number == 2)
        #expect(figure?.starterUserID == Fixture.me)
        #expect(figure?.isFinished == false)
        #expect(figure?.parts.map(\.id) == [queued.partID])
        #expect(figure?.parts.first?.drawerUserID == Fixture.me)
        #expect(figure?.parts.first?.idea == idea)
        // The drawing is on the phone, and the server has no file for it yet.
        #expect(figure?.parts.first?.drawingMediaAssetID == nil)
    }

    @Test func aQueuedBodyAddsToTheFigureInProgress() {
        let queued = Fixture.queuedPart(figure: 1, partIndex: 1)
        let current = Fixture.figure(1, parts: 1)
        let state = Fixture.state(game: Fixture.game(figure: 1, partIndex: 1, turn: Fixture.me), current: current)

        let resolution = resolve(state, pending: Fixture.pending(parts: [queued]))

        #expect(resolution.phase == .waiting)
        #expect(resolution.part == .legs)
        let figure = resolution.figure
        #expect(figure?.id == current.id)
        #expect(figure?.parts.map(\.partIndex) == [0, 1])
        #expect(figure?.parts.first == current.parts.first)
        #expect(figure?.parts.last?.id == queued.partID)
        #expect(figure?.isFinished == false)
    }

    @Test func queuedLegsFinishTheFigureHereAndWaitForTheServer() {
        let queued = Fixture.queuedPart(figure: 2, partIndex: 2)
        let current = Fixture.figure(2, parts: 2)
        let state = Fixture.state(game: Fixture.game(figure: 2, partIndex: 2, turn: Fixture.me), current: current)

        let resolution = resolve(state, pending: Fixture.pending(parts: [queued]))

        #expect(resolution.phase == .waitingToSync)
        #expect(resolution.turnPhase == .waitingToSync)
        #expect(resolution.part == nil)
        #expect(resolution.isWaitingToSend)
        let figure = resolution.figure
        #expect(figure?.isFinished == true)
        #expect(figure?.finishedAt == queued.createdAt)
        #expect(figure?.parts.map(\.partIndex) == [0, 1, 2])
    }

    @Test func aQueuedPartWithTheRevealOfAnEarlierFigureStillWaitingKeepsTheRevealFirst() {
        let earlier = Fixture.figure(1)
        let current = Fixture.figure(2, parts: 2)
        let state = Fixture.state(
            game: Fixture.game(figure: 2, partIndex: 2, turn: Fixture.me),
            current: current,
            recent: [earlier]
        )

        let resolution = resolve(state, pending: Fixture.pending(parts: [Fixture.queuedPart(figure: 2, partIndex: 2)]))

        #expect(resolution.phase == .reveal)
        #expect(resolution.figure == earlier)
        #expect(resolution.turnPhase == .waitingToSync)
        #expect(resolution.turnPhase != .reveal)
    }

    @Test func aQueuedPartTheServerAlreadyHasIsIgnored() {
        // The head reached the server. The queued copy has not been removed yet.
        let queued = Fixture.queuedPart(figure: 2, partIndex: 0)
        let current = Fixture.figure(2, parts: 1)
        let state = Fixture.state(game: Fixture.game(figure: 2, partIndex: 1, turn: Fixture.partner), current: current)

        let resolution = resolve(state, pending: Fixture.pending(parts: [queued]))

        #expect(resolution.phase == .waiting)
        #expect(resolution.part == .body)
        #expect(resolution.figure == current)
        #expect(resolution.figure?.parts.first?.drawingMediaAssetID != nil)
        #expect(resolution.isWaitingToSend)
    }

    @Test func aQueuedPartForAnotherFigureGameOrTurnIsIgnored() {
        let game = Fixture.game(figure: 2, partIndex: 0, turn: Fixture.me)
        let state = Fixture.state(game: game)

        // A head of an earlier figure, a head of a later one, and the same head of another game.
        let head = Fixture.queuedPart(figure: 2, partIndex: 0)
        let otherGame = ExquisiteCorpseSubmitPartPayload(
            gameID: UUID(),
            figureID: head.figureID,
            partID: head.partID,
            partIndex: head.partIndex,
            coupleID: head.coupleID,
            drawing: head.drawing,
            strip: head.strip,
            idea: nil,
            createdAt: head.createdAt
        )
        let earlier = Fixture.queuedPart(figure: 0, partIndex: 0)
        let later = Fixture.queuedPart(figure: 4, partIndex: 0)
        for stale in [earlier, later, otherGame] {
            let resolution = resolve(state, pending: Fixture.pending(parts: [stale]))
            #expect(resolution.phase == .drawing)
            #expect(resolution.part == .head)
            #expect(resolution.figure == nil)
        }

        // The same head when it is the partner's turn.
        let partnersTurn = Fixture.state(game: Fixture.game(figure: 2, partIndex: 0, turn: Fixture.partner))
        let ignored = resolve(partnersTurn, pending: Fixture.pending(parts: [head]))
        #expect(ignored.phase == .waiting)
        #expect(ignored.part == .head)
        #expect(ignored.figure == nil)
    }

    @Test func aQueuedBodyForAnotherFigureIsIgnored() {
        let current = Fixture.figure(1, parts: 1)
        let state = Fixture.state(game: Fixture.game(figure: 1, partIndex: 1, turn: Fixture.me), current: current)
        let wrongFigure = Fixture.queuedPart(figure: 3, partIndex: 1)

        let resolution = resolve(state, pending: Fixture.pending(parts: [wrongFigure]))

        #expect(resolution.phase == .drawing)
        #expect(resolution.figure == current)
    }

    @Test func aQueuedBodyWithoutTheFigureInTheStateIsIgnored() {
        let state = Fixture.state(game: Fixture.game(figure: 1, partIndex: 1, turn: Fixture.me), current: nil)

        let resolution = resolve(state, pending: Fixture.pending(parts: [Fixture.queuedPart(figure: 1, partIndex: 1)]))

        #expect(resolution.phase == .drawing)
    }

    @Test func onlyAPartWaitingMakesTheResolutionWaitToSend() {
        let state = Fixture.state(game: Fixture.game(figure: 2, partIndex: 0, turn: Fixture.me))
        let marks = Fixture.pending(revealsSeen: [Fixture.figureID(1)])

        #expect(!resolve(state, pending: marks).isWaitingToSend)
        let part = Fixture.pending(parts: [Fixture.queuedPart(figure: 2, partIndex: 0)])
        #expect(resolve(nil, pending: part).isWaitingToSend)
    }
}
