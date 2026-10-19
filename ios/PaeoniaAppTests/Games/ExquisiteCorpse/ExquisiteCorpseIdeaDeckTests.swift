import Testing
@testable import PaeoniaApp

struct ExquisiteCorpseIdeaDeckTests {
    private let ideas = [
        RemoteExquisiteCorpseIdea(id: "head-grandma", text: "a grandma"),
        RemoteExquisiteCorpseIdea(id: "head-robot", text: "a robot"),
        RemoteExquisiteCorpseIdea(id: "head-owl", text: "an owl"),
    ]

    @Test func nextWalksThroughTheDeckAndStartsOverAtTheEnd() {
        var deck = ExquisiteCorpseIdeaDeck(ideas: ideas)

        #expect(deck.next() == ideas[1])
        #expect(deck.next() == ideas[2])
        #expect(deck.next() == ideas[0])
        #expect(deck.current == ideas[0])
        #expect(deck.next() == ideas[1])
    }

    @Test func aDraftRestoresTheSameIdea() {
        var deck = ExquisiteCorpseIdeaDeck(ideas: ideas, restoring: "head-robot")

        #expect(deck.current == ideas[1])
        // Shuffle goes on from the restored idea.
        #expect(deck.next() == ideas[2])
    }

    @Test func anIdeaThatIsNotInTheDeckStartsAtTheFirstOne() {
        let deck = ExquisiteCorpseIdeaDeck(ideas: ideas, restoring: "head-from-another-language")

        #expect(deck.current == ideas[0])
        #expect(ExquisiteCorpseIdeaDeck(ideas: ideas, restoring: nil).current == ideas[0])
    }

    @Test func anEmptyDeckHasNoIdeaAndNeverTraps() {
        var deck = ExquisiteCorpseIdeaDeck(ideas: [], restoring: "head-robot")

        #expect(deck.current == nil)
        #expect(deck.next() == nil)
        #expect(deck.current == nil)
    }
}
