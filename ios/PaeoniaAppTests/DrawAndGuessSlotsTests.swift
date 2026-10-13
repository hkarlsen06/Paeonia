import Testing
@testable import PaeoniaApp

struct DrawAndGuessSlotsTests {
    private func tile(_ id: Int, _ letter: Character) -> DrawAndGuessTile {
        DrawAndGuessTile(id: id, letter: letter)
    }

    @Test func oneSlotPerLetterWithGapsForSpaces() {
        let slots = DrawAndGuessSlots(answer: "  ice   cream ")

        #expect(slots.slots.count == 9)
        #expect(slots.slots.filter(\.isGap).map(\.id) == [3])
        #expect(slots.answer == "ICE CREAM")
    }

    @Test func theRightWordChipNumbersLettersButNotSpaces() {
        let numbered = DrawAndGuessAnswer.numberedCharacters(of: "ice  cream")

        #expect(String(numbered.map(\.character)) == "ICE CREAM")
        #expect(numbered.map(\.letter) == [0, 1, 2, nil, 3, 4, 5, 6, 7])
        // The reveal lights all 8 letters, so the last letter must be number 7.
        #expect(numbered.compactMap(\.letter).max() == DrawAndGuessAnswer.letters(of: "ice cream").count - 1)
    }

    @Test func tilesFillTheNextFreeSlotAndSkipGaps() {
        var slots = DrawAndGuessSlots(answer: "a b")

        let first = slots.place(tile(0, "A"))
        #expect(first)
        let second = slots.place(tile(1, "B"))
        #expect(second)

        #expect(slots.slots[0].tile?.letter == "A")
        #expect(slots.slots[1].tile == nil)
        #expect(slots.slots[2].tile?.letter == "B")
        #expect(slots.isFull)
        let third = slots.place(tile(2, "C"))
        #expect(!third)
    }

    @Test func aTileCannotBePlacedTwice() {
        var slots = DrawAndGuessSlots(answer: "aa")

        let once = slots.place(tile(0, "A"))
        #expect(once)
        let twice = slots.place(tile(0, "A"))
        #expect(!twice)
        #expect(slots.placedTileIDs == [0])
    }

    @Test func tappingASlotReturnsItsTileAndTheNextTileFillsTheHole() {
        var slots = DrawAndGuessSlots(answer: "cat")
        slots.place(tile(0, "C"))
        slots.place(tile(1, "A"))
        slots.place(tile(2, "T"))

        let removed = slots.remove(at: 1)

        #expect(removed == tile(1, "A"))
        #expect(slots.placedTileIDs == [0, 2])
        #expect(slots.status == .incomplete)
        let refilled = slots.place(tile(3, "A"))
        #expect(refilled)
        #expect(slots.status == .correct)
    }

    @Test func removingFromAnEmptySlotGapOrBadIndexDoesNothing() {
        var slots = DrawAndGuessSlots(answer: "a b")

        let fromEmpty = slots.remove(at: 0)
        #expect(fromEmpty == nil)
        let fromGap = slots.remove(at: 1)
        #expect(fromGap == nil)
        let pastEnd = slots.remove(at: 9)
        #expect(pastEnd == nil)
        let beforeStart = slots.remove(at: -1)
        #expect(beforeStart == nil)
    }

    @Test func clearReturnsEveryTile() {
        var slots = DrawAndGuessSlots(answer: "cat")
        slots.place(tile(0, "C"))
        slots.place(tile(1, "A"))

        slots.clear()

        #expect(slots.placedTileIDs.isEmpty)
        #expect(!slots.isFull)
    }

    @Test func correctWordWithSpacesMatches() {
        var slots = DrawAndGuessSlots(answer: "ice cream")
        for (index, letter) in "ICECREAM".enumerated() {
            #expect(slots.status == .incomplete)
            slots.place(tile(index, letter))
        }

        #expect(slots.filledWord == "ICE CREAM")
        #expect(slots.status == .correct)
    }

    @Test func comparisonIgnoresCaseOfTheAnswer() {
        var slots = DrawAndGuessSlots(answer: "Blåbær")
        for (index, letter) in "BLÅBÆR".enumerated() {
            slots.place(tile(index, letter))
        }

        #expect(slots.status == .correct)
    }

    @Test func wrongFullWordIsReportedAndClearingReturnsAllTiles() {
        var slots = DrawAndGuessSlots(answer: "cat")
        for (index, letter) in "HAT".enumerated() {
            slots.place(tile(index, letter))
        }

        #expect(slots.status == .wrong)
        #expect(slots.filledWord == "HAT")

        slots.clear()
        #expect(slots.status == .incomplete)
        #expect(slots.placedTileIDs.isEmpty)
    }

    @Test func sameLettersInTheWrongOrderIsWrong() {
        var slots = DrawAndGuessSlots(answer: "cat")
        for (index, letter) in "ACT".enumerated() {
            slots.place(tile(index, letter))
        }

        #expect(slots.status == .wrong)
    }

    @Test func tilesFillAroundTheGapInOrder() {
        var slots = DrawAndGuessSlots(answer: "ab cd")
        for (index, letter) in "ABCD".enumerated() {
            slots.place(tile(index, letter))
        }

        #expect(slots.status == .correct)
        #expect(slots.filledWord == "AB CD")
    }

    @Test func aRevealedSlotShowsTheAnswerNotAWrongTile() {
        var slots = DrawAndGuessSlots(answer: "cat")
        slots.place(tile(0, "T"))

        #expect(slots.shownLetter(at: 0, isRevealed: false, isLit: false) == "T")
        #expect(slots.shownLetter(at: 0, isRevealed: true, isLit: false) == "C")
        // An empty slot fills in only when the reveal reaches it.
        #expect(slots.shownLetter(at: 1, isRevealed: true, isLit: false) == nil)
        #expect(slots.shownLetter(at: 1, isRevealed: true, isLit: true) == "A")
    }
}
