import Foundation
import Testing
@testable import PaeoniaApp

/// Writing a line, giving a dare, ending the story, naming it, and moving past
/// the finished story. Every move is checked in the pending operations.
@MainActor
struct StoryChainViewModelMoveTests {
    private typealias Fixture = StoryChainFixture
    private typealias Env = StoryChainTestEnvironment

    /// My turn to write line 2, after the partner's line 1.
    private func writingAfterPartner(dare: String? = nil, words: [RemoteStoryDareWord]? = nil) -> Env {
        Env(state: Env.writing(
            turn: Fixture.me,
            lines: [Env.line(1, by: Fixture.partner, text: "She took the night bus.", dare: dare)],
            words: words
        ))
    }

    // MARK: Writing a line

    @Test func aLineIsQueuedWithItsNormalizedText() async throws {
        let environment = writingAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()

        viewModel.draft = "  The door\n  opened.  "
        await viewModel.sendLine()

        let line = try #require(await environment.queuedLines().first)
        #expect(line.text == "The door opened.")
        #expect(line.storyID == Fixture.storyID)
        #expect(!line.isLast)
        #expect(line.dareWord == nil)
        #expect(line.dareWordID == nil)
        #expect(line.createdAt == GameFixture.now)
        #expect(viewModel.draft.isEmpty)
        #expect(viewModel.dareToGive == nil)
        #expect(viewModel.phase == .waitingForLine)
    }

    @Test func aSuggestedWordGoesByItsId() async throws {
        let environment = writingAfterPartner(words: Env.words)
        let viewModel = environment.viewModel()
        await viewModel.reload()
        #expect(viewModel.wordChoices == Env.words)

        viewModel.giveDare(Env.words[0])
        #expect(viewModel.dareToGive == StoryChainDare(word: "lantern", wordID: "en-lantern"))
        viewModel.draft = "The door opened."
        await viewModel.sendLine()

        let line = try #require(await environment.queuedLines().first)
        #expect(line.dareWord == "lantern")
        #expect(line.dareWordID == "en-lantern")
        #expect(viewModel.dareToGive == nil)
    }

    @Test func aTypedWordGoesLowercaseWithoutAnId() async throws {
        let environment = writingAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()

        #expect(viewModel.giveOwnDare("  Café "))
        #expect(viewModel.dareToGive == StoryChainDare(word: "café", wordID: nil))
        viewModel.draft = "The door opened."
        await viewModel.sendLine()

        let line = try #require(await environment.queuedLines().first)
        #expect(line.dareWord == "café")
        #expect(line.dareWordID == nil)
    }

    @Test func aTypedWordMustBeOneWordOfTwoToTwentyLetters() async {
        let viewModel = writingAfterPartner().viewModel()
        await viewModel.reload()

        for rejected in ["", "a", "two words", "x1y", "ab-cd", String(repeating: "a", count: 21)] {
            #expect(!viewModel.giveOwnDare(rejected))
        }
        #expect(viewModel.dareToGive == nil)

        #expect(viewModel.giveOwnDare("smørbrød"))
        viewModel.removeDare()
        #expect(viewModel.dareToGive == nil)
    }

    @Test func aDraftBetweenTwoAndTwoHundredFortyCharactersCanBeSent() async {
        let viewModel = writingAfterPartner().viewModel()
        await viewModel.reload()

        for (text, canSend) in [("a", false), ("ab", true), (String(repeating: "a", count: 240), true),
                                (String(repeating: "a", count: 241), false)] {
            viewModel.draft = text
            #expect(viewModel.canSend == canSend)
        }
    }

    @Test func twoTapsOnSendQueueTheLineOnce() async {
        let environment = writingAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        viewModel.draft = "The door opened."

        async let first: Void = viewModel.sendLine()
        async let second: Void = viewModel.sendLine()
        _ = await (first, second)

        #expect(await environment.queuedLines().count == 1)
    }

    // MARK: The dare check

    @Test func thePartnersDareBlocksSendingUntilTheLineUsesIt() async throws {
        let environment = writingAfterPartner(dare: "anchor")
        let viewModel = environment.viewModel()
        await viewModel.reload()
        #expect(viewModel.dareForMe == "anchor")

        viewModel.draft = "A quiet morning."
        #expect(viewModel.lineCheck.usesDare == false)
        #expect(!viewModel.lineCheck.canSend)
        #expect(!viewModel.canSend)
        await viewModel.sendLine()
        #expect(await environment.queuedLines().isEmpty)
        #expect(viewModel.draft == "A quiet morning.")
        #expect(viewModel.phase == .writing)

        // The word may sit inside a longer word, in any case.
        viewModel.draft = "The Anchorage was empty."
        #expect(viewModel.lineCheck.usesDare == true)
        #expect(viewModel.canSend)
        await viewModel.sendLine()
        let line = try #require(await environment.queuedLines().first)
        #expect(line.text == "The Anchorage was empty.")
    }

    @Test func noDareMeansNothingToUse() async {
        let viewModel = writingAfterPartner().viewModel()
        await viewModel.reload()

        viewModel.draft = "A quiet morning."
        #expect(viewModel.dareForMe == nil)
        #expect(viewModel.lineCheck.usesDare == nil)
        #expect(viewModel.canSend)
    }

    // MARK: Ending the story

    @Test func lineTwentyIsAlwaysTheLastAndCarriesNoDare() async throws {
        let environment = Env(state: Env.writing(turn: Fixture.me, lines: Fixture.lines(19, starter: Fixture.partner)))
        let viewModel = environment.viewModel()
        await viewModel.reload()
        #expect(viewModel.nextLineNumber == 20)
        #expect(viewModel.mustEndHere)
        #expect(viewModel.isLastLine)
        #expect(!viewModel.canGiveDare)

        viewModel.giveDare(Env.words[0])
        #expect(viewModel.dareToGive == nil)
        #expect(!viewModel.giveOwnDare("lantern"))
        viewModel.isLastLine = false
        #expect(viewModel.isLastLine)

        // Even a dare that got in some other way is not sent.
        viewModel.dareToGive = StoryChainDare(word: "lantern", wordID: nil)
        viewModel.draft = "And that was the end."
        await viewModel.sendLine()

        let line = try #require(await environment.queuedLines().first)
        #expect(line.isLast)
        #expect(line.dareWord == nil)
        #expect(line.dareWordID == nil)
        #expect(viewModel.phase == .waitingForName)
    }

    @Test func fromLineEightTheWriterCanMakeTheLineTheLast() async throws {
        let environment = Env(state: Env.writing(
            turn: Fixture.me,
            lines: Fixture.lines(7, starter: Fixture.partner),
            words: Env.words
        ))
        let viewModel = environment.viewModel()
        await viewModel.reload()
        #expect(viewModel.nextLineNumber == 8)
        #expect(viewModel.canEndHere)
        #expect(!viewModel.mustEndHere)
        #expect(!viewModel.isLastLine)
        #expect(viewModel.canGiveDare)

        viewModel.giveDare(Env.words[1])
        viewModel.isLastLine = true
        #expect(viewModel.isLastLine)
        // Nobody writes after the last line, so the dare goes.
        #expect(viewModel.dareToGive == nil)
        #expect(!viewModel.canGiveDare)

        viewModel.isLastLine = false
        #expect(viewModel.canGiveDare)
        viewModel.isLastLine = true
        viewModel.draft = "They never found out."
        await viewModel.sendLine()

        let line = try #require(await environment.queuedLines().first)
        #expect(line.isLast)
        #expect(line.dareWord == nil)
        #expect(viewModel.phase == .waitingForName)
        #expect(!viewModel.isLastLine)
    }

    @Test func beforeLineEightTheSwitchDoesNothing() async throws {
        let environment = Env(state: Env.writing(turn: Fixture.me, lines: Fixture.lines(6, starter: Fixture.me)))
        let viewModel = environment.viewModel()
        await viewModel.reload()
        #expect(viewModel.nextLineNumber == 7)
        #expect(!viewModel.canEndHere)

        viewModel.isLastLine = true
        #expect(!viewModel.isLastLine)
        viewModel.draft = "The street went quiet."
        await viewModel.sendLine()

        let line = try #require(await environment.queuedLines().first)
        #expect(!line.isLast)
    }

    // MARK: A new turn

    /// Words that were never sent stay when another phone of this person moves
    /// the story on. Losing them would drop what the person wrote.
    @Test func unsentWordsCarryOverToTheNextTurn() async {
        let environment = writingAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        viewModel.draft = "Half a line"

        await viewModel.reload()
        #expect(viewModel.draft == "Half a line")

        let later = Env.writing(
            turn: Fixture.me,
            lines: Fixture.lines(3, starter: Fixture.partner),
            version: 2
        )
        await environment.cache.saveState(later, ownerUserID: Fixture.me)
        await viewModel.reload()
        #expect(viewModel.nextLineNumber == 4)
        #expect(viewModel.draft == "Half a line")
    }

    // MARK: Leftovers from the background

    @Test func aNoticeLeftByABackgroundSendShowsOnce() async {
        let environment = writingAfterPartner()
        let viewModel = environment.viewModel()
        await environment.cache.recordNotice(.moveRejected, ownerUserID: Fixture.me)

        await viewModel.reload()
        #expect(viewModel.notice == .moveRejected)

        viewModel.clearNotice()
        await viewModel.reload()
        #expect(viewModel.notice == nil)
    }

    @Test func tryAgainAsksForAnotherSendThenReadsTheServer() async {
        let environment = writingAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        let asked = AskCounter()
        viewModel.setLocalChangeSyncHandler { await asked.add() }

        await viewModel.retrySend()

        #expect(await asked.count == 1)
        #expect(environment.storyGateway.calls.contains("load"))
    }
}

private actor AskCounter {
    private(set) var count = 0

    func add() {
        count += 1
    }
}
