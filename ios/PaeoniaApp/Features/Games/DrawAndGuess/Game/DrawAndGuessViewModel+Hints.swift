import Foundation

// "Show a letter": each hint places a random letter of the answer in its slot.
// The phone picks the letters and only tells the server how many it showed.
extension DrawAndGuessViewModel {
    /// How many letters the hints showed this round.
    var hintCount: Int {
        slots.hintCount
    }

    /// The "Show a letter" button works. Hints stop one letter short of the
    /// whole word.
    var canShowLetter: Bool {
        guard phase.allowsGuessing, !isShowingWrongGuess, slots.status != .correct,
              let round, tilesRoundID == round.id, !round.isFinished
        else { return false }
        return hintCount < slots.maxHints && slots.nextHintIndex(seed: hintSeed(round.id)) != nil
    }

    /// The first hint of a round costs the bonuses, which only "Against each
    /// other" has. The screen asks before it shows that hint.
    var needsHintWarning: Bool {
        hintCount == 0 && settings?.playStyle == .against
    }

    /// Places a random unrevealed letter in its slot. A tile that sits in that
    /// slot goes back first. The slot is locked afterwards.
    func showLetter() {
        guard canShowLetter, let round, let index = slots.nextHintIndex(seed: hintSeed(round.id)) else { return }
        var updated = slots
        guard placeHint(at: index, in: &updated) else { return }
        slots = updated
        persistHints(of: round.id)
        updateSpeedBonus()
    }

    /// Puts the hinted letters of a round back after the screen was closed or
    /// the app relaunched. Called when the tiles for the round are built.
    func restoreHints(for round: DrawAndGuessRoundView) {
        guard let indexes = persistedHints[round.id], !indexes.isEmpty else { return }
        var updated = slots
        for index in indexes {
            placeHint(at: index, in: &updated)
        }
        slots = updated
    }

    /// The round and the hint count pick the letter, so the order is random but
    /// never changes for a round.
    private func hintSeed(_ roundID: UUID) -> String {
        "\(roundID.uuidString.lowercased())-hint-\(hintCount)"
    }

    /// Fills the slot with a tile that has the answer's letter. A tile the player
    /// put in that slot, or in a slot where that letter is wrong, goes back to the
    /// grid when it is the one needed.
    @discardableResult
    private func placeHint(at index: Int, in slots: inout DrawAndGuessSlots) -> Bool {
        let letters = Array(slots.answer)
        guard letters.indices.contains(index) else { return false }
        let letter = letters[index]
        slots.remove(at: index)
        var tile = tiles.first { $0.letter == letter && !slots.placedTileIDs.contains($0.id) }
        let misplaced = slots.slots.first { $0.tile?.letter == letter && !$0.isHint && letters[$0.id] != letter }
        if tile == nil, let other = misplaced {
            // Every tile with this letter sits in a slot. The hinted slot lacks it, so at
            // least one of them is in a wrong place. The player's right letters stay.
            tile = slots.remove(at: other.id)
        }
        guard let tile else { return false }
        slots.placeHint(tile, at: index)
        return true
    }

    private func persistHints(of roundID: UUID) {
        let indexes = slots.hintedIndexes
        persistedHints[roundID] = indexes
        guard let userID = currentUserID else { return }
        let cache = dependencies.cache
        Task { await cache.saveHints(indexes, roundID: roundID, ownerUserID: userID) }
    }
}
