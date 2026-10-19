import Foundation
import Testing
@testable import PaeoniaApp

/// Ludo's piece colors on the screen's view model: the pick going out with the
/// first move and losing to the partner's pick of the same color.
@MainActor
struct BoardGameViewModelLudoColorTests {
    private typealias Fixture = BoardGameDataFixture

    private let harness = BoardGameHarness()

    private func ludoGame(
        first: BoardGameSide = .me,
        moves: [Int] = [],
        myColor: LudoColor = .pink,
        partnerColor: LudoColor = .lavender
    ) -> RemoteBoardGame {
        Fixture.game(
            kind: .ludo,
            first: harness.id(of: first),
            moves: moves,
            myColor: myColor,
            partnerColor: partnerColor
        )
    }

    private func openLudo(_ game: RemoteBoardGame) async -> BoardGameViewModel<LudoBoard> {
        await harness.save(game)
        var dependencies = harness.env.dependencies()
        dependencies.boardGamesGateway = harness.gateway
        dependencies.boardGamesCache = harness.cache
        let viewModel = BoardGameViewModel<LudoBoard>(
            kind: .ludo,
            timing: BoardGameMoveTiming(mine: .zero, partner: .zero),
            dependencies: dependencies,
            heartbeatInterval: .seconds(3_600),
            tickInterval: .seconds(3_600),
            sleep: harness.sleeps.sleep
        )
        viewModel.configure(
            participants: GameParticipants(
                currentUserID: harness.me,
                coupleID: Fixture.coupleID,
                partnerName: "Robin",
                currentName: "Alex"
            )
        )
        await viewModel.start(prefersReducedMotion: true)
        let caughtUp = await waitUntil { !viewModel.isReplaying }
        #expect(caughtUp)
        return viewModel
    }

    // MARK: Picking

    @Test func theColorMyPartnerHasCannotBePicked() async {
        let viewModel = await openLudo(ludoGame())
        defer { viewModel.stop() }

        viewModel.pickColor(.lavender)

        #expect(viewModel.ludoColors == .standard)
        #expect(viewModel.pendingColorPick == nil)
    }

    @Test func thePickGoesToTheServerWithTheFirstMoveOnly() async {
        let game = ludoGame()
        let viewModel = await openLudo(game)
        defer { viewModel.stop() }
        viewModel.pickColor(.sky)

        await viewModel.play(15)

        #expect(await harness.queuedMoves() == [Fixture.move(15, on: game, expectedVersion: 1, ludoColor: .sky)])
        #expect(viewModel.colorChoice == nil)
        #expect(viewModel.ludoColors == LudoColorPair(mine: .sky, partner: .lavender))
    }

    @Test func pickingMyOwnColorAgainSendsNothing() async {
        let game = ludoGame()
        let viewModel = await openLudo(game)
        defer { viewModel.stop() }
        viewModel.pickColor(.gold)
        viewModel.pickColor(.pink)

        await viewModel.play(15)

        #expect(await harness.queuedMoves() == [Fixture.move(15, on: game, expectedVersion: 1)])
    }

    @Test func aColorMyPartnerTakesFirstDropsMyPick() async {
        // The partner starts, and I pick gold while I wait.
        let viewModel = await openLudo(ludoGame(first: .partner))
        defer { viewModel.stop() }
        viewModel.pickColor(.gold)
        #expect(viewModel.ludoColors.mine == .gold)

        // The partner's first move arrives with gold.
        await harness.save(ludoGame(first: .partner, moves: [2], partnerColor: .gold))
        await viewModel.reload()

        #expect(viewModel.ludoColors == LudoColorPair(mine: .pink, partner: .gold))
        #expect(viewModel.pendingColorPick == nil)
        #expect(viewModel.colorChoice?.options.filter(\.isTaken).map(\.color) == [.gold])
    }
}
