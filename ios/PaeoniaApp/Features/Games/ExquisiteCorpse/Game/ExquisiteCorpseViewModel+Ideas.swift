import Foundation

// The idea chip. The server deals a deck for the part, and the chip walks
// through it. Whatever chip shows when the person taps Done is saved with the
// part. The chip is also kept in the cache as it changes, so a relaunch shows
// the same idea.
extension ExquisiteCorpseViewModel {
    /// Sets the chip and the deck for the part the canvas now holds.
    func restoreIdea(for partID: UUID) {
        let ideas = state?.ideas ?? []
        let savedID = savedIdeaIDs[partID]
        hasIdeas = !ideas.isEmpty
        ideaDeck = ExquisiteCorpseIdeaDeck(ideas: ideas, restoring: savedID)
        idea = savedID.flatMap { id in ideas.first { $0.id == id } }
    }

    /// The server's deck changed while the person drew, such as after a new game
    /// language. The chip stays, and the deck goes on from it.
    func refreshIdeaDeck() {
        let ideas = state?.ideas ?? []
        hasIdeas = !ideas.isEmpty
        guard ideas != ideaDeck?.ideas else { return }
        ideaDeck = ExquisiteCorpseIdeaDeck(ideas: ideas, restoring: idea?.id)
    }

    /// "Need an idea?": shows the chip.
    func askIdea() {
        guard phase == .drawing, let partID = ownPartID, idea == nil, let next = ideaDeck?.current else { return }
        setIdea(next, partID: partID)
    }

    /// Deals the next idea. After the last one comes the first.
    func shuffleIdea() {
        guard phase == .drawing, let partID = ownPartID, idea != nil, let next = ideaDeck?.next() else { return }
        setIdea(next, partID: partID)
    }

    /// Clears the chip. The next "Need an idea?" deals a new idea.
    func removeIdea() {
        guard phase == .drawing, let partID = ownPartID, idea != nil else { return }
        ideaDeck?.next()
        setIdea(nil, partID: partID)
    }

    private func setIdea(_ newIdea: RemoteExquisiteCorpseIdea?, partID: UUID) {
        idea = newIdea
        savedIdeaIDs[partID] = newIdea?.id
        guard let userID = currentUserID else { return }
        // One after the other, so the last choice is the one kept.
        let previous = ideaSaveTask
        let cache = cache
        ideaSaveTask = Task {
            await previous?.value
            await cache.saveIdea(newIdea?.id, partID: partID, ownerUserID: userID)
        }
    }
}
