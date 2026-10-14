import Foundation

/// The ideas the server dealt for the part this person draws next, and which one
/// the chip shows. The server shuffles the deck with the part as the seed, so
/// reopening the game deals the same order. Shuffle walks through it and starts
/// over at the end.
nonisolated struct ExquisiteCorpseIdeaDeck: Equatable, Sendable {
    let ideas: [RemoteExquisiteCorpseIdea]
    private(set) var index: Int

    /// Starts at the idea with `ideaID`, so a draft restores the same chip. An
    /// id that is not in the deck, such as one from before the game language
    /// changed, starts at the first idea.
    init(ideas: [RemoteExquisiteCorpseIdea], restoring ideaID: String? = nil) {
        self.ideas = ideas
        index = ideaID.flatMap { id in ideas.firstIndex { $0.id == id } } ?? 0
    }

    /// Nil when the server dealt no ideas.
    var current: RemoteExquisiteCorpseIdea? {
        ideas.indices.contains(index) ? ideas[index] : nil
    }

    /// Moves to the next idea and returns it. After the last idea comes the first.
    @discardableResult
    mutating func next() -> RemoteExquisiteCorpseIdea? {
        guard !ideas.isEmpty else {
            return nil
        }
        index = (index + 1) % ideas.count
        return current
    }
}
