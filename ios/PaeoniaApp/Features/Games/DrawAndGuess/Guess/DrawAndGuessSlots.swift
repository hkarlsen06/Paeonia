import Foundation

/// The answer slots above the tiles: one per letter, a gap for each space.
/// The UI shows a tile as used while its id is in `placedTileIDs`.
nonisolated struct DrawAndGuessSlots: Equatable, Sendable {
    struct Slot: Identifiable, Equatable, Sendable {
        let id: Int
        /// A space between words. Gaps never hold a tile.
        let isGap: Bool
        fileprivate(set) var tile: DrawAndGuessTile?
    }

    enum Status: Equatable, Sendable {
        /// At least one slot is still empty.
        case incomplete
        case correct
        /// Every slot is filled with the wrong word. The UI shakes the slots,
        /// then calls `clear()` to return all tiles.
        case wrong
    }

    private(set) var slots: [Slot]
    /// The answer in capitals, with single spaces.
    let answer: String

    init(answer: String) {
        let normalized = DrawAndGuessAnswer.normalized(answer)
        self.answer = normalized
        slots = normalized.enumerated().map { offset, character in
            Slot(id: offset, isGap: character == " ", tile: nil)
        }
    }

    var placedTileIDs: Set<Int> {
        Set(slots.compactMap { $0.tile?.id })
    }

    var isFull: Bool {
        slots.allSatisfy { $0.isGap || $0.tile != nil }
    }

    /// The letters placed so far in slot order, with a space for each gap.
    /// Empty slots are skipped, so read it once `isFull`.
    var filledWord: String {
        String(slots.compactMap { $0.isGap ? " " : $0.tile?.letter })
    }

    /// Compares the filled word to the answer, ignoring case.
    var status: Status {
        guard isFull else {
            return .incomplete
        }
        return filledWord.uppercased() == answer ? .correct : .wrong
    }

    /// Puts the tile in the first empty slot. Returns false when every slot is
    /// full or the tile is already placed.
    @discardableResult
    mutating func place(_ tile: DrawAndGuessTile) -> Bool {
        guard !placedTileIDs.contains(tile.id),
              let index = slots.firstIndex(where: { !$0.isGap && $0.tile == nil })
        else {
            return false
        }
        slots[index].tile = tile
        return true
    }

    /// Takes the tile out of a slot, as when the player taps the slot. Returns
    /// nil for a gap, an empty slot, or an index out of range. Later tiles stay
    /// where they are.
    @discardableResult
    mutating func remove(at index: Int) -> DrawAndGuessTile? {
        guard slots.indices.contains(index), let tile = slots[index].tile else {
            return nil
        }
        slots[index].tile = nil
        return tile
    }

    /// Returns every tile.
    mutating func clear() {
        for index in slots.indices {
            slots[index].tile = nil
        }
    }
}
