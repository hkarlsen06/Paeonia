import Foundation
import Testing
@testable import PaeoniaApp

/// "Show a letter": each hint places a random letter of the answer in its slot
/// and locks the slot.
@MainActor
struct DrawAndGuessHintTests {
    private var guessing: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
    }

    private func guessingModel(
        _ env: GamesTestEnvironment? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
    ) async -> (GamesTestEnvironment, DrawAndGuessViewModel) {
        let env = env ?? GamesTestEnvironment(state: guessing)
        let viewModel = env.viewModel(sleep: sleep)
        await viewModel.reload()
        return (env, viewModel)
    }

    private func tile(_ letter: Character, in viewModel: DrawAndGuessViewModel) throws -> DrawAndGuessTile {
        let used = viewModel.slots.placedTileIDs
        return try #require(viewModel.tiles.first { $0.letter == letter && !used.contains($0.id) })
    }

    private func letters(in viewModel: DrawAndGuessViewModel) -> [Character?] {
        viewModel.slots.slots.map { $0.tile?.letter }
    }

    /// Every hinted slot holds the answer's letter for that slot.
    private func hintsAreRight(in viewModel: DrawAndGuessViewModel) -> Bool {
        let answer = Array(viewModel.slots.answer)
        let shown = letters(in: viewModel)
        return viewModel.slots.hintedIndexes.allSatisfy { shown[$0] == answer[$0] }
    }

    // MARK: Slots

    @Test func aHintLocksItsSlotAndSurvivesClearAndRemove() throws {
        var slots = DrawAndGuessSlots(answer: "hot dog")
        let hot = DrawAndGuessTile(id: 0, letter: "H")
        let other = DrawAndGuessTile(id: 1, letter: "X")

        slots.place(other)
        slots.placeHint(hot, at: 0)

        #expect(slots.hintCount == 1)
        #expect(slots.hintedIndexes == [0])
        #expect(slots.slots[0].tile == hot)
        #expect(slots.remove(at: 0) == nil)
        slots.clear()
        #expect(slots.slots[0].tile == hot)
        #expect(slots.nextHintIndex(seed: "a") != 0)
    }

    @Test func theNextHintSkipsGapsAndHintedLetters() {
        var slots = DrawAndGuessSlots(answer: "ab cd")
        slots.placeHint(DrawAndGuessTile(id: 0, letter: "A"), at: 0)
        // Index 2 is the space between the words.
        let picks = Set((0..<40).compactMap { slots.nextHintIndex(seed: "round-\($0)") })
        #expect(picks == [1, 3, 4])
        #expect(slots.maxHints == 3)
    }

    @Test func theNextHintIsRandomButTheSameForTheSameSeed() {
        let slots = DrawAndGuessSlots(answer: "umbrella")
        let firstPicks = Set((0..<40).compactMap { slots.nextHintIndex(seed: "round-\($0)") })
        #expect(firstPicks.count > 3)
        #expect(slots.nextHintIndex(seed: "same") == slots.nextHintIndex(seed: "same"))
    }

    @Test func theNextHintSkipsLettersThePlayerHasRight() {
        var slots = DrawAndGuessSlots(answer: "abc")
        slots.place(DrawAndGuessTile(id: 0, letter: "A"))
        slots.place(DrawAndGuessTile(id: 1, letter: "X"))
        let picks = Set((0..<40).compactMap { slots.nextHintIndex(seed: "round-\($0)") })
        #expect(picks == [1, 2])
    }

    // MARK: View model

    @Test func eachHintPlacesARightLetterAndTheOrderIsTheSameEveryTime() async {
        let (_, viewModel) = await guessingModel()
        #expect(viewModel.phase == .guessing)

        viewModel.showLetter()
        viewModel.showLetter()

        #expect(viewModel.hintCount == 2)
        #expect(hintsAreRight(in: viewModel))
        let (_, again) = await guessingModel()
        again.showLetter()
        again.showLetter()
        #expect(again.slots.hintedIndexes == viewModel.slots.hintedIndexes)
    }

    @Test func aTileInTheSlotGoesBackFirstAndDuplicateLettersStillWork() async throws {
        let (_, viewModel) = await guessingModel()
        // Both L tiles sit in the first two slots, so the hints need them back.
        viewModel.placeTile(try tile("L", in: viewModel))
        viewModel.placeTile(try tile("L", in: viewModel))
        #expect(letters(in: viewModel).prefix(2) == ["L", "L"])

        for _ in 0..<7 {
            viewModel.showLetter()
        }

        #expect(viewModel.hintCount == 7)
        #expect(hintsAreRight(in: viewModel))
        // Every hinted tile is its own tile.
        let hintedTiles = viewModel.slots.hintedIndexes.compactMap { viewModel.slots.slots[$0].tile?.id }
        #expect(Set(hintedTiles).count == 7)
    }

    @Test func aHintNeverTakesALetterThePlayerHasRight() async throws {
        let (_, viewModel) = await guessingModel()
        // "umbrella": U and M in place, right.
        viewModel.placeTile(try tile("U", in: viewModel))
        viewModel.placeTile(try tile("M", in: viewModel))

        for _ in 0..<5 {
            viewModel.showLetter()
        }

        #expect(letters(in: viewModel).prefix(2) == ["U", "M"])
        #expect(!viewModel.slots.hintedIndexes.contains(0))
        #expect(!viewModel.slots.hintedIndexes.contains(1))
        #expect(hintsAreRight(in: viewModel))
    }

    @Test func hintsStopOneLetterShortOfTheWholeWord() async {
        let (_, viewModel) = await guessingModel()

        for _ in 0..<7 {
            #expect(viewModel.canShowLetter)
            viewModel.showLetter()
        }

        #expect(viewModel.hintCount == 7)
        #expect(!viewModel.canShowLetter)
        viewModel.showLetter()
        #expect(viewModel.hintCount == 7)
        // "umbrella" has 8 letters. The last one is left for the player.
        #expect(letters(in: viewModel).last == .some(nil))
    }

    @Test func aHintedSlotDoesNotTakeATapAndStaysAfterAWrongWord() async throws {
        let (_, viewModel) = await guessingModel()
        viewModel.showLetter()
        let hintIndex = try #require(viewModel.slots.hintedIndexes.first)
        let hinted = letters(in: viewModel)[hintIndex]

        viewModel.removeTile(atSlot: hintIndex)
        #expect(letters(in: viewModel)[hintIndex] == hinted)

        // Fill the other seven slots with letters that are wrong for them.
        let answer = Array(viewModel.slots.answer)
        for index in answer.indices where index != hintIndex {
            let used = viewModel.slots.placedTileIDs
            let wrong = try #require(viewModel.tiles.first { $0.letter != answer[index] && !used.contains($0.id) })
            viewModel.placeTile(wrong)
        }
        #expect(viewModel.wrongGuessCount == 1)
        let returned = await waitUntil { !viewModel.isShowingWrongGuess }
        #expect(returned)

        #expect(letters(in: viewModel)[hintIndex] == hinted)
        #expect(viewModel.slots.hintedIndexes == [hintIndex])
        #expect(letters(in: viewModel).indices.allSatisfy { $0 == hintIndex || letters(in: viewModel)[$0] == nil })
        viewModel.clearGuess()
        #expect(letters(in: viewModel)[hintIndex] == hinted)
    }

    @Test func theFirstHintAsksOnlyWhenTheCoupleCompetes() async {
        let (_, against) = await guessingModel()
        #expect(against.needsHintWarning)
        against.showLetter()
        #expect(!against.needsHintWarning)

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
        let (_, togetherModel) = await guessingModel(GamesTestEnvironment(state: together))
        #expect(!togetherModel.needsHintWarning)
    }

    @Test func aHintTakesTheSpeedLabelAndLineAway() async {
        let (_, viewModel) = await guessingModel()
        #expect(viewModel.speedBonus != .hidden)

        viewModel.showLetter()

        #expect(viewModel.speedBonus == .hidden)
        #expect(!viewModel.speedBonusIsAvailable)
    }

    @Test func aCorrectGuessAfterHintsSendsTheHintCountAndNoSpeedBonus() async throws {
        let (env, viewModel) = await guessingModel()
        viewModel.showLetter()
        viewModel.showLetter()

        // The hints showed two random letters. The rest of the answer fills the other slots.
        let answer = Array(viewModel.slots.answer)
        for index in answer.indices where answer[index] != " " && !viewModel.slots.hintedIndexes.contains(index) {
            viewModel.placeTile(try tile(answer[index], in: viewModel))
        }

        var queued: [PendingSyncOperationSnapshot] = []
        for _ in 0..<200 {
            queued = await env.queued(.submitGameGuess)
            if !queued.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let payload = try JSONDecoder().decode(GameGuessPayload.self, from: try #require(queued.first?.requestData))
        #expect(payload.isCorrect)
        #expect(payload.hintsUsed == 2)
        #expect(payload.speedBonus == 0)
        let revealed = await waitUntil { viewModel.phase == .reveal }
        #expect(revealed)
        // The queued win carries the phone's prediction: no bonuses after a hint.
        #expect(viewModel.reveal?.speedBonus == 0)
        #expect(viewModel.reveal?.firstTryBonus == 0)
        #expect(viewModel.reveal?.hintsUsed == 2)
    }

    @Test func aFirstTryWithoutHintsPredictsTheFirstTryBonus() async throws {
        let (_, viewModel) = await guessingModel()

        for letter in "UMBRELLA" {
            viewModel.placeTile(try tile(letter, in: viewModel))
        }

        let revealed = await waitUntil { viewModel.phase == .reveal }
        #expect(revealed)
        #expect(viewModel.reveal?.firstTryBonus == 1)
        #expect(viewModel.reveal?.speedBonus == 2)
        #expect(viewModel.reveal?.isConfirmed == false)
    }

    // MARK: Persistence

    @Test func hintsSurviveLeavingTheScreenAndARelaunch() async throws {
        let (env, viewModel) = await guessingModel()
        viewModel.showLetter()
        viewModel.showLetter()

        var saved: [GameRoundHints] = []
        for _ in 0..<200 {
            saved = await env.cache.document(ownerUserID: GameFixture.me).hints
            if saved.first?.slotIndexes.count == 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let hinted = viewModel.slots.hintedIndexes
        #expect(hinted.count == 2)
        #expect(saved == [GameRoundHints(roundID: GameFixture.roundID, slotIndexes: hinted)])

        let reopened = env.viewModel()
        await reopened.reload()

        #expect(reopened.slots.hintedIndexes == hinted)
        #expect(hintsAreRight(in: reopened))
        // The restored hints count: no alert, no speed bonus.
        #expect(!reopened.needsHintWarning)
        #expect(reopened.speedBonus == .hidden)
    }

    @Test func theCacheKeepsTheHintsOfTheLatestRoundsOnly() async {
        let cache = InMemoryGamesCache()
        for index in 0..<25 {
            await cache.saveHints([index % 5], roundID: UUID(), ownerUserID: GameFixture.me)
        }
        let kept = UUID()
        await cache.saveHints([1, 2], roundID: kept, ownerUserID: GameFixture.me)
        await cache.saveHints([1, 2, 4], roundID: kept, ownerUserID: GameFixture.me)

        let hints = await cache.document(ownerUserID: GameFixture.me).hints

        #expect(hints.count == 20)
        #expect(hints.last == GameRoundHints(roundID: kept, slotIndexes: [1, 2, 4]))
        #expect(hints.filter { $0.roundID == kept }.count == 1)
    }
}
