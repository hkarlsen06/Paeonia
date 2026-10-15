import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// The reveal, the seen mark and reactions.
extension DrawAndGuessViewModelTests {
    // MARK: Reveal, result seen and reactions

    private var solvedByMe: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me),
            round: GameFixture.round(
                state: .solved,
                drawer: GameFixture.partner,
                hasDrawing: true,
                solveMs: 18_400,
                speedBonus: 1,
                firstTryBonus: 1,
                personalBest: true
            ),
            choices: GameFixture.choices
        )
    }

    @Test func theRevealShowsTimePointsAndBothBonuses() async {
        let viewModel = environment(solvedByMe).viewModel()
        await viewModel.reload()

        let reveal = viewModel.reveal
        #expect(viewModel.phase == .reveal)
        #expect(reveal?.outcome == .iSolvedIt)
        #expect(reveal?.solveDuration == 18.4)
        #expect(reveal?.speedBonus == 1)
        #expect(reveal?.firstTryBonus == 1)
        #expect(reveal?.personalBest == true)
        #expect(reveal?.pointsForMe == 4)
        #expect(reveal?.pointsForCouple == 2)
        #expect(reveal?.isConfirmed == true)
        #expect(viewModel.isNextTurnMine)
    }

    @Test func continuingFromTheRevealSavesTheSeenMarkOnThePhoneAtOnce() async throws {
        let env = environment(solvedByMe)
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .reveal)

        await viewModel.continueFromReveal()

        // The mark waits in the queue for the network. Continue never waits for it.
        #expect(viewModel.phase == .chooseWord)
        let payload = try JSONDecoder().decode(
            GameResultSeenPayload.self,
            from: try #require(await env.queued(.markGameRoundResultSeen).first?.requestData)
        )
        #expect(payload.roundID == GameFixture.roundID)
        #expect(await env.queued(.markGameRoundResultSeen).count == 1)
    }

    @Test func aResultTheServerAlreadyKnowsAsSeenIsNotShownAgain() async {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me),
            round: GameFixture.round(
                state: .solved,
                drawer: GameFixture.partner,
                hasDrawing: true,
                resultSeenBy: [GameFixture.me]
            ),
            choices: GameFixture.choices
        )
        let viewModel = environment(state).viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .chooseWord)
        #expect(viewModel.reveal == nil)
    }

    @Test func aReactionShowsAtOnceIsQueuedAndAnotherTapClearsIt() async throws {
        let env = environment(solvedByMe)
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.reveal?.reaction == nil)

        await viewModel.react(.love)
        #expect(viewModel.reveal?.reaction == .love)
        #expect(await env.queued(.setGameRoundReaction).count == 1)

        await viewModel.react(.wow)
        #expect(viewModel.reveal?.reaction == .wow)

        await viewModel.react(.wow)
        #expect(viewModel.reveal?.reaction == nil)
        let payloads = try await env.queued(.setGameRoundReaction).map {
            try JSONDecoder().decode(GameReactionPayload.self, from: try #require($0.requestData))
        }
        #expect(payloads.map(\.reaction) == [.love, .wow, nil])
        #expect(Set(payloads.map(\.roundID)) == [GameFixture.roundID])
    }

    @Test func aReactionStaysAfterTheScreenReadsTheQueueAgain() async {
        let env = environment(solvedByMe)
        let viewModel = env.viewModel()
        await viewModel.reload()
        await viewModel.react(.laugh)

        let reopened = env.viewModel()
        await reopened.reload()

        #expect(reopened.reveal?.reaction == .laugh)
    }

    @Test func onlyTheGuesserCanReact() async {
        let solvedAsDrawer = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner),
            round: GameFixture.round(state: .solved, drawer: GameFixture.me, hasDrawing: true, solveMs: 9_000)
        )
        let env = environment(solvedAsDrawer)
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.react(.love)

        #expect(await env.queued(.setGameRoundReaction).isEmpty)
        #expect(viewModel.reveal?.reaction == nil)
    }

    @Test func theDrawerSeesTheGuessersReactionWhenItArrives() async {
        let waiting = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner),
            round: GameFixture.round(state: .solved, drawer: GameFixture.me, hasDrawing: true, solveMs: 9_000)
        )
        let env = environment(waiting)
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.reveal?.reaction == nil)

        await env.cache.saveState(
            GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner),
                round: GameFixture.round(
                    state: .solved,
                    drawer: GameFixture.me,
                    hasDrawing: true,
                    solveMs: 9_000,
                    reaction: .laugh
                )
            ),
            ownerUserID: GameFixture.me
        )
        await viewModel.reload()

        #expect(viewModel.reveal?.reaction == .laugh)
        #expect(viewModel.round?.guesserReaction == .laugh)
    }

    @Test func aReactionAfterTheDrawerContinuedShowsWhileWaitingForTheNextWord() async {
        let round = GameFixture.round(state: .solved, drawer: GameFixture.me, hasDrawing: true, solveMs: 9_000)
        let game = GameFixture.game(state: .choosingWord, turn: GameFixture.partner)
        let env = environment(GameFixture.state(settings: GameFixture.settings(), game: game, round: round))
        let viewModel = env.viewModel()
        await viewModel.reload()
        await viewModel.continueFromReveal()
        #expect(viewModel.phase == .waitingForWord)
        #expect(viewModel.reactionToMyLastDrawing == nil)

        let reacted = GameFixture.round(
            state: .solved,
            drawer: GameFixture.me,
            hasDrawing: true,
            solveMs: 9_000,
            reaction: .love
        )
        await env.cache.saveState(
            GameFixture.state(settings: GameFixture.settings(), game: game, round: reacted),
            ownerUserID: GameFixture.me
        )
        await viewModel.reload()

        #expect(viewModel.phase == .waitingForWord)
        #expect(viewModel.reactionToMyLastDrawing == .love)
    }

    @Test func aMissedRoundRevealsTheWordForWhoeverGaveUp() async {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner),
            round: GameFixture.round(state: .missed, drawer: GameFixture.me, hasDrawing: true)
        )
        let viewModel = environment(state).viewModel()
        await viewModel.reload()

        #expect(viewModel.reveal?.outcome == .partnerGaveUp)
        #expect(viewModel.reveal?.pointsForMe == 0)
        #expect(!viewModel.isNextTurnMine)
    }

    @Test func theSpeedBonusIsOpenWhenTheCoupleCompetesAndHiddenWhenTheyPlayTogether() async {
        let viewModel = environment(guessing).viewModel()
        await viewModel.reload()
        #expect(viewModel.speedBonus != .hidden)

        let together = GameFixture.state(
            settings: RemoteGameSettings(
                coupleID: DeveloperScenarioFixture.coupleID,
                playStyle: .together,
                language: .en,
                updatedByUserID: GameFixture.me,
                createdAt: GameFixture.now,
                updatedAt: GameFixture.now
            ),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
        let togetherModel = environment(together).viewModel()
        await togetherModel.reload()
        #expect(togetherModel.speedBonus == .hidden)
    }

    @Test func theFirstTurnOfAGameIsKnown() async {
        let viewModel = environment(yourTurn).viewModel()
        await viewModel.reload()

        // The fixture game is on turn 4.
        #expect(!viewModel.isFirstTurn)
    }
}
