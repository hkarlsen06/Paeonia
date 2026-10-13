import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// The whole Draw & Guess flow through `DrawAndGuessViewModel`, on in-memory parts.
@MainActor
struct DrawAndGuessViewModelTests {
    private func environment(
        _ state: RemoteDrawAndGuessState,
        hasSeenSettings: Bool = true
    ) -> GamesTestEnvironment {
        GamesTestEnvironment(state: state, hasSeenSettings: hasSeenSettings)
    }

    private var yourTurn: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil),
            choices: GameFixture.choices
        )
    }

    private var guessing: RemoteDrawAndGuessState {
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
        #expect(viewModel.reveal?.speedBonus == nil)
        let guess = try JSONDecoder().decode(
            GameGuessPayload.self,
            from: try #require(await env.queued(.submitGameGuess).first?.requestData)
        )
        #expect(guess.guess == "umbrella")
        #expect(guess.isCorrect)
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

    // MARK: Live

    @Test func aLiveSolveWhileDrawingRevealsAndSendsTheDrawingAsItIs() async throws {
        let drawingState = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.me)
        )
        let env = environment(drawingState)
        let viewModel = env.viewModel()
        await viewModel.reload()
        viewModel.board.canvasDidLayout(side: 320)
        viewModel.board.replace(with: GameFixture.umbrella())
        #expect(viewModel.phase == .drawing)

        // The partner solves it live: the server's state moves on.
        await env.cache.saveState(
            GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner),
                round: GameFixture.round(
                    state: .solved,
                    drawer: GameFixture.me,
                    attempts: [("cat", false), ("umbrella", true)],
                    solveMs: 9_000,
                    speedBonus: 1
                )
            ),
            ownerUserID: GameFixture.me
        )
        await viewModel.reload()

        #expect(viewModel.phase == .reveal)
        #expect(viewModel.reveal?.outcome == .partnerSolvedIt)
        #expect(viewModel.reveal?.pointsForMe == 2)
        #expect(viewModel.reveal?.attempts.map(\.text) == ["cat", "umbrella"])
        let sent = await waitUntil { viewModel.round?.isDrawingSent == true }
        #expect(sent)
        #expect(await env.queued(.submitGameDrawing).count == 1)
        #expect(viewModel.finalDrawing != nil)
    }

    @Test func theGuesserWatchingLiveKeepsTheLiveCanvasWhenTheDrawerPressesDone() async throws {
        let drawingState = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.partner)
        )
        let env = environment(drawingState)
        let (room, connection) = makeOfflineLiveRoom()
        let viewModel = env.viewModel(live: room)
        viewModel.configure(participants: GameFixture.participants)
        await viewModel.reload()
        #expect(viewModel.phase == .waitingForDrawing)

        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "drawing"))
        sendPartnerCanvasSnapshot(on: connection)
        viewModel.recompute()
        #expect(viewModel.phase == .watchingLive)
        #expect(viewModel.partnerPresence == .drawing)

        await env.cache.saveState(guessing, ownerUserID: GameFixture.me)
        await viewModel.reload()

        #expect(viewModel.phase == .guessing)
        #expect(viewModel.guessSource == .live)
    }

    // MARK: Replay

    @Test func theReplayStartsOnceTheDrawingIsLoadedAndTheGuesserIsMarkedAsHavingSeenIt() async {
        let env = environment(guessing)
        let viewModel = env.viewModel()
        await viewModel.reload()

        let ready = await waitUntil { viewModel.isReplayReady }

        #expect(ready)
        #expect(viewModel.guessSource == .replay)
        #expect(env.transfer.downloads == [GameFixture.assetID])
        let marked = await waitUntil { true }
        #expect(marked)
        let seen = await {
            for _ in 0..<100 {
                if env.gateway.seenRounds == [GameFixture.roundID] { return true }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return false
        }()
        #expect(seen)
        // Past the end, the whole drawing shows.
        #expect(viewModel.replayDrawing(atWall: .greatestFiniteMagnitude, side: 320).strokes.count == 3)
        // At the very start only the first point of the first stroke shows.
        #expect(viewModel.replayDrawing(atWall: -1, side: 320).strokes.count < 3)
    }

    // MARK: Reveal and save

    private var solvedByMe: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me),
            round: GameFixture.round(
                state: .solved,
                drawer: GameFixture.partner,
                hasDrawing: true,
                solveMs: 18_400,
                speedBonus: 1
            ),
            choices: GameFixture.choices
        )
    }

    @Test func theRevealShowsTimePointsAndTheSpeedBonus() async {
        let viewModel = environment(solvedByMe).viewModel()
        await viewModel.reload()

        let reveal = viewModel.reveal
        #expect(viewModel.phase == .reveal)
        #expect(reveal?.outcome == .iSolvedIt)
        #expect(reveal?.solveDuration == 18.4)
        #expect(reveal?.speedBonus == 1)
        #expect(reveal?.pointsForMe == 3)
        #expect(reveal?.pointsForCouple == 2)
        #expect(reveal?.isConfirmed == true)
        #expect(viewModel.isNextTurnMine)
    }

    @Test func continuingFromTheRevealCountsAsNoToSaving() async {
        let env = environment(solvedByMe)
        let viewModel = env.viewModel()
        await viewModel.reload()
        _ = await waitUntil { viewModel.savePrompt == .ask }
        #expect(viewModel.savePrompt == .ask)

        await viewModel.continueFromReveal()

        // The answer goes out in the background, so Continue never waits for it.
        _ = await waitUntil { env.gateway.savePromptAnswers == [GameFixture.roundID] }
        #expect(env.gateway.savePromptAnswers == [GameFixture.roundID])
        #expect(viewModel.phase == .chooseWord)
        #expect(viewModel.savePrompt == .hidden)
        #expect(await env.cache.document(ownerUserID: GameFixture.me).acknowledgedRoundIDs == [GameFixture.roundID])
    }

    @Test func savingRendersTheDrawingAndQueuesItForMemories() async throws {
        let env = environment(solvedByMe)
        let viewModel = env.viewModel()
        await viewModel.reload()
        _ = await waitUntil { viewModel.savePrompt == .ask && viewModel.finalDrawing != nil }

        await viewModel.saveToMemories()

        #expect(viewModel.savePrompt == .saving)
        let payload = try JSONDecoder().decode(
            GameSaveRoundPayload.self,
            from: try #require(await env.queued(.saveGameRoundToMemories).first?.requestData)
        )
        #expect(payload.roundID == GameFixture.roundID)
        #expect(payload.imageData?.isEmpty == false)
        #expect(payload.memoryDate == MemoryTimeline.localDateString(for: GameFixture.now))
    }

    @Test func aMissedRoundRevealsTheWordForWhoeverGaveUp() async {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner),
            round: GameFixture.round(
                state: .missed,
                drawer: GameFixture.me,
                hasDrawing: true,
                mySaveResponse: .notNow
            )
        )
        let viewModel = environment(state).viewModel()
        await viewModel.reload()

        #expect(viewModel.reveal?.outcome == .partnerGaveUp)
        #expect(viewModel.reveal?.pointsForMe == 0)
        #expect(viewModel.savePrompt == .hidden)
        #expect(!viewModel.isNextTurnMine)
    }

    @Test func theSaveQuestionAlsoShowsOnTheWaitingScreenAfterTheResult() async {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner, roundID: nil),
            round: GameFixture.round(state: .solved, drawer: GameFixture.me, hasDrawing: true, solveMs: 9_000, speedBonus: 1)
        )
        let env = environment(state)
        await env.cache.acknowledgeRound(GameFixture.roundID, ownerUserID: GameFixture.me)
        let viewModel = env.viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .waitingForWord)
        #expect(viewModel.savePrompt == .ask)
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
