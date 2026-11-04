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

    @Test func unseenPiccanteEndingStaysOutOfPreviewsIncludingDuringRematch() async throws {
        let finished = DeveloperPiccanteFixture.state(for: .piccanteResult)
        let end = try #require(finished.game)
        let cache = InMemoryPiccanteCache(state: finished)
        var dependencies = DeveloperGamesScenarioFactory.dependencies(for: .piccanteResult)
        dependencies.piccanteCache = cache
        let loader = GameChatPreviewLoader(dependencies: dependencies)
        func check() async throws {
            let preview = await loader.load(for: .piccante, userID: finished.userID)
            guard case .piccante(let box) = preview else { Issue.record("Expected a box"); return }
            #expect(box.bites == Array(end.bites.dropLast()))
            #expect(box.chilis.isEmpty)
            #expect(box.myChili == nil)
            #expect(box.phase != .finished)
            #expect(box.winnerUserID == nil)
        }
        try await check()
        var rematch = DeveloperPiccanteFixture.state(for: .piccanteChoose)
        rematch.game?.gameNumber = 2
        rematch.game?.version = end.version + 1
        rematch.unseenResult = end
        await cache.saveState(rematch, ownerUserID: finished.userID)
        try await check()
        rematch.unseenResult = nil
        await cache.saveState(rematch, ownerUserID: finished.userID)
        #expect(await loader.load(for: .piccante, userID: finished.userID) == .piccante(end))
    }

    private func loader(_ state: RemoteExquisiteCorpseState) -> GameChatPreviewLoader {
        var dependencies = DeveloperGamesScenarioFactory.dependencies(for: .exquisiteCorpseReveal)
        dependencies.exquisiteCorpseCache = InMemoryExquisiteCorpseCache(state: state, ownerUserID: me)
        return GameChatPreviewLoader(dependencies: dependencies)
    }
}
