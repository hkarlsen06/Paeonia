import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// The whole Draw & Guess flow through `DrawAndGuessViewModel`, on in-memory parts.
@MainActor
struct DrawAndGuessViewModelTests {
    func environment(
        _ state: RemoteDrawAndGuessState,
        hasSeenSettings: Bool = true
    ) -> GamesTestEnvironment {
        GamesTestEnvironment(state: state, hasSeenSettings: hasSeenSettings)
    }

    var yourTurn: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil),
            choices: GameFixture.choices
        )
    }

    var guessing: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
    }

    private func tile(_ letter: Character, in viewModel: DrawAndGuessViewModel) throws -> DrawAndGuessTile {
        let used = viewModel.slots.placedTileIDs
        return try #require(viewModel.tiles.first { $0.letter == letter && !used.contains($0.id) })
    }

    private func type(_ word: String, into viewModel: DrawAndGuessViewModel) throws {
        for letter in word.uppercased() where letter != " " {
            viewModel.placeTile(try tile(letter, in: viewModel))
        }
    }

    // MARK: Phases from server states

    @Test func theViewModelFollowsTheCachedStateIntoEachPhase() async {
        let env = environment(yourTurn)
        let viewModel = env.viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .chooseWord)
        #expect(viewModel.choices.map(\.word) == ["pizza", "umbrella", "volcano"])
        #expect(viewModel.score == .against(mine: 8, partner: 5))
        #expect(viewModel.settings?.language == .en)
    }

    @Test func theGuesserNeverGetsTheWordChoices() async {
        // Even if choices were in the cache, a phase that is not "choose word" offers none.
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner, roundID: nil),
            choices: GameFixture.choices
        )
        let viewModel = environment(state).viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .waitingForWord)
        #expect(viewModel.choices.isEmpty)
    }

    @Test func theGuesserGetsTilesSeededByTheRoundIdAndTheGameLanguage() async {
        let viewModel = environment(guessing).viewModel()
        await viewModel.reload()

        let expected = DrawAndGuessTiles.make(
            answer: "umbrella",
            language: .en,
            seed: GameFixture.roundID.uuidString.lowercased()
        )
        #expect(viewModel.phase == .guessing)
        #expect(viewModel.tiles == expected)
        #expect(viewModel.slots.answer == "UMBRELLA")
    }

    // MARK: Picking and drawing

    @Test func pickingAWordQueuesItAndStartsTheRoundOnThePhone() async throws {
        let env = environment(yourTurn)
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.chooseWord(try #require(viewModel.choices.first { $0.difficulty == .medium }))

        #expect(viewModel.phase == .drawing)
        #expect(viewModel.round?.word == "umbrella")
        #expect(viewModel.isWaitingToSend)
        let queued = await env.queued(.pickDrawWord)
        #expect(queued.count == 1)
        let payload = try JSONDecoder().decode(GamePickWordPayload.self, from: try #require(queued.first?.requestData))
        #expect(payload.wordID == "en-medium-umbrella")
        #expect(payload.gameID == GameFixture.gameID)
    }

    @Test func aCustomWordIsCheckedAndSentWithoutAWordId() async throws {
        let env = environment(yourTurn)
        let viewModel = env.viewModel()
        await viewModel.reload()

        viewModel.customWord = "a"
        #expect(viewModel.customWordValidation == .invalid(.tooShort))
        viewModel.customWord = "x1y"
        #expect(viewModel.customWordValidation == .invalid(.notAllowedCharacter))
        viewModel.customWord = "  my  moms   dog "
        #expect(viewModel.customWordValidation == .valid("my moms dog"))

        await viewModel.chooseCustomWord()

        let payload = try JSONDecoder().decode(
            GamePickWordPayload.self,
            from: try #require(await env.queued(.pickDrawWord).first?.requestData)
        )
        #expect(payload.choice == .custom)
        #expect(payload.word == "my moms dog")
        #expect(payload.wordID == nil)
        #expect(payload.points == 2)
        #expect(viewModel.customWord.isEmpty)
    }

    @Test func aCustomWordThatBreaksTheRulesIsNotSent() async {
        let env = environment(yourTurn)
        let viewModel = env.viewModel()
        await viewModel.reload()
        viewModel.customWord = "one two three four"

        await viewModel.chooseCustomWord()

        #expect(viewModel.customWordValidation == .invalid(.tooManyWords))
        #expect(await env.queued(.pickDrawWord).isEmpty)
    }

    @Test func doneQueuesTheDrawingAfterThePickAndMovesOnToWaiting() async throws {
        let env = environment(yourTurn)
        let viewModel = env.viewModel()
        await viewModel.reload()
        await viewModel.chooseWord(try #require(viewModel.choices.first))
        viewModel.board.canvasDidLayout(side: 320)
        viewModel.board.replace(with: GameFixture.umbrella())

        #expect(viewModel.canFinishDrawing)
        await viewModel.finishDrawing()

        #expect(viewModel.phase == .waitingForGuess)
        let ready = try await env.pending.readyOperations(ownerUserID: GameFixture.me, limit: 10, now: .distantFuture)
        #expect(ready.compactMap(\.operationKind) == [.pickDrawWord, .submitGameDrawing])
        #expect(viewModel.round?.isDrawingSent == true)
    }

    @Test func aDraftSurvivesAndIsRestoredWhenTheRoundOpensAgain() async throws {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.me)
        )
        let env = environment(state)
        env.drawingStore.saveDraft(
            GameFixture.umbrella().dataRepresentation(),
            ownerUserID: GameFixture.me,
            roundID: GameFixture.roundID
        )
        let viewModel = env.viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .drawing)
        #expect(viewModel.board.drawing.strokes.count == 3)
        viewModel.board.canvasDidLayout(side: 320)
        viewModel.saveDraftNow()
        #expect(env.drawingStore.draft(ownerUserID: GameFixture.me, roundID: GameFixture.roundID) != nil)
    }

    // MARK: Guessing

    @Test func aCorrectGuessIsKnownAtOnceAndQueuedForTheServer() async throws {
        let env = environment(guessing)
        let viewModel = env.viewModel()
        await viewModel.reload()

        try type("umbrella", into: viewModel)
        let queued = await waitUntil { viewModel.phase == .reveal }

        #expect(queued)
        #expect(viewModel.solvedCount == 1)
        #expect(viewModel.reveal?.outcome == .iSolvedIt)
        #expect(viewModel.reveal?.isConfirmed == false)
        let guess = try JSONDecoder().decode(
            GameGuessPayload.self,
            from: try #require(await env.queued(.submitGameGuess).first?.requestData)
        )
        #expect(guess.guess == "umbrella")
        #expect(guess.isCorrect)
        // Until the server answers, the reveal shows the bonus the phone claimed.
        #expect(viewModel.reveal?.speedBonus == guess.speedBonus)
    }

    @Test func aWrongGuessShakesThenReturnsTheTilesAndIsStillSent() async throws {
        let env = environment(guessing)
        let viewModel = env.viewModel(sleep: { _ in })
        await viewModel.reload()

        try type("umbrelle", into: viewModel)

        #expect(viewModel.wrongGuessCount == 1)
        #expect(viewModel.isShowingWrongGuess || viewModel.slots.placedTileIDs.isEmpty)
        let cleared = await waitUntil { viewModel.slots.placedTileIDs.isEmpty && !viewModel.isShowingWrongGuess }
        #expect(cleared)
        #expect(viewModel.phase == .guessing)
        let queued = await waitUntil { viewModel.round?.attempts.contains { $0.isPending } == true }
        #expect(queued)
        #expect(await env.queued(.submitGameGuess).count == 1)
    }

    @Test func showMeEndsTheRoundAsMissedWithoutWaitingForTheNetwork() async {
        let env = environment(guessing)
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.giveUp()

        #expect(viewModel.phase == .reveal)
        #expect(viewModel.reveal?.outcome == .iGaveUp)
        #expect(viewModel.reveal?.word == "umbrella")
        #expect(await env.queued(.giveUpGameRound).count == 1)
    }

    @Test func theDrawerCannotGuessAndTilesStayClosedOutsideGuessing() async throws {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.me)
        )
        let viewModel = environment(state).viewModel()
        await viewModel.reload()

        #expect(viewModel.tiles.isEmpty)
        viewModel.placeTile(DrawAndGuessTile(id: 0, letter: "U"))
        #expect(viewModel.slots.placedTileIDs.isEmpty)
        await viewModel.giveUp()
        #expect(viewModel.phase == .drawing)
    }
}
