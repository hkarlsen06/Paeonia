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

    @Test func receivedHintsOnlyMarkFilledCorrectLettersAndSkipGaps() {
        let slots = DrawAndGuessSlots(
            answer: "a bcd",
            letters: ["A", " ", "X", nil, "D"],
            hintedIndexes: [-1, 0, 1, 2, 3, 4, 99]
        )

        #expect(slots.hintedIndexes == [0, 4])
        #expect(slots.slots[1].tile == nil)
        #expect(slots.slots[2].tile?.letter == "X")
        #expect(slots.slots[3].tile == nil)
    }

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
}
