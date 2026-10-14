import Foundation
import Testing
@testable import PaeoniaApp

/// The composer's text is kept on the phone, and the words of a line the server
/// refused come back into the next composer, so no words are lost.
@MainActor
struct StoryChainViewModelSavedDraftTests {
    private typealias Fixture = StoryChainFixture
    private typealias Env = StoryChainTestEnvironment

    @Test func aSavedDraftComesBackIntoAnEmptyComposer() async {
        let environment = Env.myTurnAfterPartner()
        await environment.cache.saveDraft("The lighthouse blinked twice.", ownerUserID: Fixture.me)
        let viewModel = environment.viewModel()

        await viewModel.reload()

        #expect(viewModel.draft == "The lighthouse blinked twice.")
    }

    @Test func aSavedDraftThatIsAlreadyALineStaysAway() async {
        // The app stopped right after Send, before the draft was forgotten.
        let environment = StoryChainTestEnvironment(state: Env.writing(
            turn: Fixture.me,
            lines: [
                Env.line(1, by: Fixture.partner),
                Env.line(2, by: Fixture.me, text: "Someone knocked."),
                Env.line(3, by: Fixture.partner),
            ]
        ))
        await environment.cache.saveDraft("Someone knocked.", ownerUserID: Fixture.me)
        let viewModel = environment.viewModel()

        await viewModel.reload()

        #expect(viewModel.draft.isEmpty)
    }

    @Test func aSavedDraftComesBackOnlyBeforeTheFirstEdit() async {
        let environment = Env.myTurnAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        viewModel.draft = "Typed."
        viewModel.draft = ""

        // A read from before the edit still holds an old draft.
        await environment.cache.saveDraft("Old words.", ownerUserID: Fixture.me)
        await viewModel.reload()

        #expect(viewModel.draft.isEmpty)
    }

    @Test func typingIsSavedAfterAPause() async {
        let environment = Env.myTurnAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()

        viewModel.draft = "Someone knocked."

        let cache = environment.cache
        let saved = await waitUntil { await cache.document(ownerUserID: Fixture.me).draft == "Someone knocked." }
        #expect(saved)
    }

    @Test func sendingForgetsTheDraft() async {
        let environment = Env.myTurnAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        viewModel.draft = "Someone knocked."

        await viewModel.sendLine()

        let cache = environment.cache
        let forgotten = await waitUntil { await cache.document(ownerUserID: Fixture.me).draft == nil }
        #expect(forgotten)
        #expect(viewModel.draft.isEmpty)
    }

    @Test func aRefusedLineComesBackIntoTheComposer() async {
        let environment = Env.myTurnAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        viewModel.draft = "Someone knocked."
        await viewModel.sendLine()

        // The handler drops the refused line from the queue and keeps its words.
        for operation in await environment.queued(.storyChainAddLine) {
            try? await environment.pending.markTerminalFailure(
                clientOperationID: operation.operation.id,
                errorDescription: "refused",
                at: Date()
            )
        }
        await environment.cache.rescueLines(["Someone knocked."], ownerUserID: Fixture.me)
        await viewModel.reload()

        #expect(viewModel.phase == .writing)
        let restored = await waitUntil { viewModel.draft == "Someone knocked." }
        #expect(restored)
        #expect(await environment.cache.document(ownerUserID: Fixture.me).rescuedLines.isEmpty)
    }

    @Test func rescuedWordsJoinWhatIsAlreadyBeingTyped() async {
        let environment = Env.myTurnAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        viewModel.draft = "A new start."

        await environment.cache.rescueLines(["The old line."], ownerUserID: Fixture.me)
        await viewModel.reload()

        let joined = await waitUntil { viewModel.draft == "A new start. The old line." }
        #expect(joined)
    }

    @Test func rescuedWordsWaitForTheNextTurnToWrite() async {
        let environment = Env.waitingOnPartner()
        await environment.cache.rescueLines(["The old line."], ownerUserID: Fixture.me)
        let viewModel = environment.viewModel()

        await viewModel.reload()

        #expect(viewModel.draft.isEmpty)
        #expect(await environment.cache.document(ownerUserID: Fixture.me).rescuedLines == ["The old line."])
    }

    @Test func aNewTurnKeepsUnsentWords() async {
        let environment = Env.myTurnAfterPartner()
        let viewModel = environment.viewModel()
        await viewModel.reload()
        viewModel.draft = "Not sent yet."

        // Another phone of this person sent line 2, and the partner wrote line 3.
        await environment.cache.saveState(
            Env.writing(
                turn: Fixture.me,
                lines: [
                    Env.line(1, by: Fixture.partner),
                    Env.line(2, by: Fixture.me),
                    Env.line(3, by: Fixture.partner),
                ],
                version: 3
            ),
            ownerUserID: Fixture.me
        )
        await viewModel.reload()

        #expect(viewModel.nextLineNumber == 4)
        #expect(viewModel.draft == "Not sent yet.")
    }
}
