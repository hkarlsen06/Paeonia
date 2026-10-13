import Foundation

/// The answer slots above the tiles: one per letter, a gap for each space.
/// The UI shows a tile as used while its id is in `placedTileIDs`.
nonisolated struct DrawAndGuessSlots: Equatable, Sendable {
    struct Slot: Identifiable, Equatable, Sendable {
        let id: Int
        /// A space between words. Gaps never hold a tile.
        let isGap: Bool
        fileprivate(set) var tile: DrawAndGuessTile?
        /// A hint placed the tile. The slot is locked: tapping it, clearing the
        /// slots and a wrong word leave it alone.
        fileprivate(set) var isHint = false
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

    /// The partner's slots as their phone shows them. `letters` has one entry per
    /// slot, nil where it is empty. Each letter gets the slot's index as its tile id.
    init(answer: String, letters: [Character?]) {
        self.init(answer: answer)
        for index in slots.indices where !slots[index].isGap && letters.indices.contains(index) {
            slots[index].tile = letters[index].map { DrawAndGuessTile(id: index, letter: $0) }
        }
    }

    /// How many slots a hint filled.
    var hintCount: Int {
        slots.count(where: \.isHint)
    }

    /// The slot indexes the hints filled, left to right.
    var hintedIndexes: [Int] {
        slots.filter(\.isHint).map(\.id)
    }

    /// Hints show at most all letters but one, or they would give the word away.
    var maxHints: Int {
        max(0, slots.count { !$0.isGap } - 1)
    }

    /// The slot the next hint fills, picked at random from the letters no hint
    /// showed yet. A letter the player already has right is skipped, so a hint
    /// always shows something new. The same seed gives the same pick on every
    /// phone and in tests.
    func nextHintIndex(seed: String) -> Int? {
        let letters = Array(answer)
        let open = slots.filter { !$0.isGap && !$0.isHint }
        let unknown = open.filter { $0.tile?.letter != letters[$0.id] }
        let pool = unknown.isEmpty ? open : unknown
        guard !pool.isEmpty else { return nil }
        var generator = DrawAndGuessSeededGenerator(seed: seed)
        return pool[generator.nextIndex(below: pool.count)].id
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

    /// Fills the slot with a hint. A tile that sits there goes back to its cell
    /// first. The caller picks a tile that is not in another slot.
    mutating func placeHint(_ tile: DrawAndGuessTile, at index: Int) {
        guard slots.indices.contains(index), !slots[index].isGap, !slots[index].isHint else { return }
        slots[index].tile = tile
        slots[index].isHint = true
    }

    /// Takes the tile out of a slot, as when the player taps the slot. Returns
    /// nil for a gap, an empty slot, a hinted slot, or an index out of range.
    /// Later tiles stay where they are.
    @discardableResult
    mutating func remove(at index: Int) -> DrawAndGuessTile? {
        guard slots.indices.contains(index), !slots[index].isHint, let tile = slots[index].tile else {
            return nil
        }
        slots[index].tile = nil
        return tile
    }

    /// The letter a slot shows. Once the round has ended it is the answer's letter,
    /// also in a slot that holds a wrong tile, so "Show me" never shows a wrong word.
    /// - Parameter isLit: The reveal reached this slot, so an empty slot fills in.
    func shownLetter(at index: Int, isRevealed: Bool, isLit: Bool) -> Character? {
        guard slots.indices.contains(index), !slots[index].isGap else { return nil }
        guard isRevealed else { return slots[index].tile?.letter }
        guard slots[index].tile != nil || isLit else { return nil }
        let letters = Array(answer)
        return letters.indices.contains(index) ? letters[index] : nil
    }

    /// Returns every tile except the ones the hints placed.
    mutating func clear() {
        for index in slots.indices where !slots[index].isHint {
            slots[index].tile = nil
        }
    }
}
