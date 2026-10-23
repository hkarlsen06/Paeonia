import Foundation
import Testing
@testable import PaeoniaApp

/// The phase a state puts the person in, from the server's rows and the parts
/// saved on the phone. The viewer is `me`. Figure 1 starts with the partner,
/// who draws its head and legs, and figure 2 starts with `me`.
struct ExquisiteCorpsePhaseTests {
    private typealias Fixture = ExquisiteCorpseFixture
    private typealias Resolution = ExquisiteCorpseResolution

    private func resolve(
        _ state: RemoteExquisiteCorpseState?,
        hasSettings: Bool = true,
        pending: ExquisiteCorpsePendingWork = .none,
        live: Bool = false
    ) -> Resolution {
        Fixture.resolver.resolve(state: state, hasSettings: hasSettings, pending: pending, isPartnerDrawingLive: live)
    }

    // MARK: Before the game

    @Test func noStateIsLoadingNoSettingsIsSetupAndNoGameIsPreparing() {
        #expect(resolve(nil).phase == .loading)
        #expect(resolve(Fixture.state(game: nil), hasSettings: false).phase == .needsSetup)
        #expect(resolve(Fixture.state(game: nil)).phase == .preparing)
        // Settings count before the game, and the state before the settings.
        #expect(resolve(nil, hasSettings: false).phase == .loading)
        let started = Fixture.state(game: Fixture.game(figure: 1, partIndex: 0, turn: Fixture.me))
        #expect(resolve(started, hasSettings: false).phase == .needsSetup)
    }

    // MARK: A turn in progress

    @Test func myTurnForTheHeadIsDrawingWithNoFigureYet() {
        let state = Fixture.state(game: Fixture.game(figure: 2, partIndex: 0, turn: Fixture.me))

        let resolution = resolve(state)

        #expect(resolution.phase == .drawing)
        #expect(resolution.part == .head)
        #expect(resolution.figure == nil)
        #expect(resolution.turnPhase == .drawing)
        #expect(!resolution.isWaitingToSend)
    }

    @Test func myTurnForTheBodyIsDrawingOnTheFigureInProgress() {
        let current = Fixture.figure(1, parts: 1)
        let state = Fixture.state(game: Fixture.game(figure: 1, partIndex: 1, turn: Fixture.me), current: current)

        let resolution = resolve(state)

        #expect(resolution.phase == .drawing)
        #expect(resolution.part == .body)
        #expect(resolution.figure == current)
    }

    @Test func thePartnersTurnIsWaitingOrWatchingWhenTheyDrawInTheLiveRoom() {
        let current = Fixture.figure(1, parts: 2)
        let state = Fixture.state(game: Fixture.game(figure: 1, partIndex: 2, turn: Fixture.partner), current: current)

        let waiting = resolve(state)
        let watching = resolve(state, live: true)

        #expect(waiting.phase == .waiting && waiting.part == .legs && waiting.figure == current)
        #expect(watching.phase == .watching && watching.part == .legs && watching.figure == current)
    }

    // MARK: Reveal

    @Test func theLegsDrawerSeesTheRevealOnceTheServerHasTheFigureThenWaitsForTheNextHead() {
        // Figure 2 started with me, so I drew its legs. Figure 3 starts with the partner.
        let finished = Fixture.figure(2)
        let game = Fixture.game(figure: 3, partIndex: 0, turn: Fixture.partner)
        let state = Fixture.state(game: game, recent: [finished])

        let reveal = resolve(state)
        #expect(reveal.phase == .reveal)
        #expect(reveal.figure == finished)
        #expect(reveal.turnPhase == .waiting)
        #expect(reveal.part == .head)

        let afterContinue = resolve(state, pending: Fixture.pending(revealsSeen: [finished.id]))
        #expect(afterContinue.phase == .waiting)
        #expect(afterContinue.turnPhase == .waiting)
        #expect(afterContinue.part == .head)
        #expect(afterContinue.figure == nil)
    }

    @Test func thePartnerSeesTheRevealBeforeDrawingTheNextHead() {
        // Figure 1 started with the partner. I drew its body, so I start figure 2.
        let finished = Fixture.figure(1)
        let state = Fixture.state(game: Fixture.game(figure: 2, partIndex: 0, turn: Fixture.me), recent: [finished])

        let reveal = resolve(state)
        #expect(reveal.phase == .reveal)
        #expect(reveal.figure == finished)
        #expect(reveal.turnPhase == .drawing)
        #expect(reveal.part == .head)

        #expect(resolve(state, pending: Fixture.pending(revealsSeen: [finished.id])).phase == .drawing)
    }

    @Test func aRevealTheServerSaysIsSeenNeverShowsAgain() {
        // A fresh install or a second phone: nothing is stored here, the server knows.
        let seen = Fixture.figure(1, revealSeen: true)
        let state = Fixture.state(game: Fixture.game(figure: 2, partIndex: 0, turn: Fixture.me), recent: [seen])

        #expect(resolve(state).phase == .drawing)
    }

    @Test func onlyTheLatestFigureCanBeAnUnseenReveal() {
        let older = Fixture.figure(1)
        let latestSeen = Fixture.figure(2, revealSeen: true)
        let latestUnseen = Fixture.figure(2)
        let game = Fixture.game(figure: 3, partIndex: 0, turn: Fixture.partner)

        // Newest first, as the server sends them.
        #expect(resolve(Fixture.state(game: game, recent: [latestSeen, older])).phase == .waiting)
        let reveal = resolve(Fixture.state(game: game, recent: [latestUnseen, older]))
        #expect(reveal.phase == .reveal)
        #expect(reveal.figure?.number == 2)
    }
}

// MARK: - Attention

extension ExquisiteCorpsePhaseTests {
    /// The partner's legs hand me the next head, named by the part, also while the
    /// figure's reveal waits. My own queued head ends it. The game's very first head is
    /// the starter's own, so it is no handover.
    @Test func thePartnersPartMakesItMyTurnUntilMyPartIsIn() {
        func attention(_ state: RemoteExquisiteCorpseState, pending: ExquisiteCorpsePendingWork = .none) -> String? {
            ExquisiteCorpseResolver.attention(resolution: resolve(state, pending: pending), game: state.game).turn
        }
        let myHead = Fixture.game(figure: 2, partIndex: 0, turn: Fixture.me)
        let state = Fixture.state(game: myHead, recent: [Fixture.figure(1)])

        let turn = attention(state)
        #expect(turn != nil)
        #expect(attention(state, pending: Fixture.pending(revealsSeen: [Fixture.figureID(1)])) == turn)
        #expect(attention(state, pending: Fixture.pending(parts: [Fixture.queuedPart(figure: 2, partIndex: 0)])) == nil)
        #expect(attention(Fixture.state(game: Fixture.game(figure: 1, partIndex: 0, turn: Fixture.me))) == nil)
    }
}
