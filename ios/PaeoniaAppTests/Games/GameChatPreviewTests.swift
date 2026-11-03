import Foundation
import Testing

@testable import PaeoniaApp

@MainActor
struct GameChatPreviewTests {
    private let me = ExquisiteCorpseDeveloperFixture.me

    @Test func unfinishedCreatureNeverShowsEvenTheViewersOwnParts() async {
        let state = ExquisiteCorpseDeveloperFixture.state(
            game: nil, current: ExquisiteCorpseDeveloperFixture.figure(1, parts: 1))
        let loader = loader(state)
        #expect(await loader.load(for: .exquisiteCorpse, userID: me) == nil)
    }

    @Test func unfinishedCreatureUsesTheLastCompleteCreature() async {
        let finished = ExquisiteCorpseDeveloperFixture.figure(1)
        let state = ExquisiteCorpseDeveloperFixture.state(
            game: nil, current: ExquisiteCorpseDeveloperFixture.figure(2, parts: 1), recent: [finished])
        #expect(
            await loader(state).load(for: .exquisiteCorpse, userID: me)
                == .creature(finished.parts.compactMap(\.drawingMediaAssetID)))
    }

    @Test func anotherAccountCannotReadThePreview() async {
        let state = ExquisiteCorpseDeveloperFixture.state(
            game: nil, current: ExquisiteCorpseDeveloperFixture.figure(1))
        #expect(await loader(state).load(for: .exquisiteCorpse, userID: UUID()) == nil)
    }

    @Test func emptyRematchKeepsTheWinningBoardUntilANewMove() async {
        let winningMoves = [0, 1, 0, 1, 0, 1, 0]
        let setup = DeveloperBoardGameSetup(
            game: .connectFour, moves: [], previous: .init(moves: winningMoves, iStarted: true))
        let game = setup.remoteGame()
        let state = RemoteBoardGames(
            userID: me, partnerUserID: ExquisiteCorpseDeveloperFixture.partner,
            coupleID: DeveloperScenarioFixture.coupleID, dataEpoch: "", games: [game])
        var dependencies = DeveloperGamesScenarioFactory.dependencies(for: .exquisiteCorpseReveal)
        dependencies.boardGamesCache = InMemoryBoardGamesCache(state: state, ownerUserID: me)
        let loader = GameChatPreviewLoader(dependencies: dependencies)
        #expect(
            await loader.load(for: .connectFour, userID: me)
                == .board(.init(kind: .connectFour, moves: winningMoves, me: .one)))
    }

    private func loader(_ state: RemoteExquisiteCorpseState) -> GameChatPreviewLoader {
        var dependencies = DeveloperGamesScenarioFactory.dependencies(for: .exquisiteCorpseReveal)
        dependencies.exquisiteCorpseCache = InMemoryExquisiteCorpseCache(state: state, ownerUserID: me)
        return GameChatPreviewLoader(dependencies: dependencies)
    }
}
