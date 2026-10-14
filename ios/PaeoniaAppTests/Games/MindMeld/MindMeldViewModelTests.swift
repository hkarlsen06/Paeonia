import Foundation
import Testing
@testable import PaeoniaApp

/// The Mind Meld flow through `MindMeldViewModel`, on in-memory parts: writing
/// and locking in, the reveal, starting a game, and the partner.
@MainActor
struct MindMeldViewModelTests {
    private let fixtures = MindMeldFixtures()

    private func environment(
        _ game: RemoteMindMeldGame?,
        overview: RemoteGamesOverview? = nil
    ) -> MindMeldTestEnvironment {
        fixtures.environment(game, overview: overview)
    }

    // MARK: Locking in

    @Test func lockingInQueuesTheWordAndMovesToWaitingAtOnce() async throws {
        let open = fixtures.open(1)
        let game = fixtures.game(rounds: [open])
        let env = environment(game)
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .write)

        viewModel.draft = "  ocean "
        #expect(viewModel.canLockIn)
        #expect(viewModel.lockIn())

        // The word shows as locked before the queue has it.
        #expect(viewModel.phase == .waiting(isQueued: true))
        #expect(viewModel.draft.isEmpty)
        await viewModel.moveTask?.value

        let queued = await env.queued(.lockMindMeldWord)
        #expect(queued.count == 1)
        let payload = try decodePayload(MindMeldLockPayload.self, queued.first)
        #expect(payload.word == "ocean")
        #expect(payload.roundID == open.id)
        #expect(payload.gameID == game.id)
        #expect(viewModel.phase == .waiting(isQueued: true))
        #expect(viewModel.round?.myWord == "ocean")
        // The first send has not failed, so the screen does not say the word is only on the phone.
        #expect(!viewModel.showsOfflineLine)
    }

    @Test func aReadBeforeTheQueueHasTheWordKeepsItLockedIn() async {
        let env = environment(fixtures.game(rounds: [fixtures.open(1)]))
        let viewModel = env.viewModel()
        await viewModel.reload()
        viewModel.draft = "ocean"
        viewModel.lockIn()

        await viewModel.reload()

        #expect(viewModel.phase == .waiting(isQueued: true))
        await viewModel.moveTask?.value
        #expect(viewModel.phase == .waiting(isQueued: true))
    }

    @Test func anEmptyOrBrokenWordIsRefused() async {
        let env = environment(fixtures.game(rounds: [fixtures.open(1)]))
        let viewModel = env.viewModel()
        await viewModel.reload()

        #expect(!viewModel.canLockIn)
        #expect(!viewModel.lockIn())

        viewModel.draft = "   "
        #expect(!viewModel.lockIn())

        viewModel.draft = "one two three four"
        #expect(viewModel.draftIssue == .tooManyWords)
        #expect(!viewModel.canLockIn)
        #expect(!viewModel.lockIn())

        viewModel.draft = String(repeating: "a", count: 31)
        #expect(viewModel.draftIssue == .tooLong)
        #expect(!viewModel.lockIn())

        viewModel.draft = "1234"
        #expect(viewModel.draftIssue == .noLetters)
        #expect(!viewModel.lockIn())

        #expect(viewModel.phase == .write)
        await viewModel.moveTask?.value
        let queued = await env.queued(.lockMindMeldWord)
        #expect(queued.isEmpty)
    }

    @Test func aWordSaidInThisGameIsRefused() async {
        let game = fixtures.game(rounds: [fixtures.revealed(1, "ocean", "sushi"), fixtures.open(2)])
        let viewModel = environment(game).viewModel()
        await viewModel.reload()
        #expect(viewModel.usedWords.count == 2)

        // Spelling does not matter, the server compares match keys.
        viewModel.draft = "O-cean"
        #expect(viewModel.draftIssue == .repeatOf("ocean"))
        #expect(!viewModel.canLockIn)
        #expect(!viewModel.lockIn())

        viewModel.draft = "oceans"
        #expect(viewModel.draftIssue == nil)
        #expect(viewModel.canLockIn)
    }

    @Test func lockingInTwiceQueuesOneWord() async {
        let env = environment(fixtures.game(rounds: [fixtures.open(1)]))
        let viewModel = env.viewModel()
        await viewModel.reload()
        viewModel.draft = "ocean"

        #expect(viewModel.lockIn())
        viewModel.draft = "sushi"
        #expect(!viewModel.lockIn())

        await viewModel.moveTask?.value
        let queued = await env.queued(.lockMindMeldWord)
        #expect(queued.count == 1)
    }

    @Test func theDraftStaysInTheSameRoundAndClearsInTheNextOne() async throws {
        let first = fixtures.open(1)
        let game = fixtures.game(rounds: [first])
        let env = environment(game)
        let viewModel = env.viewModel()
        await viewModel.reload()
        viewModel.draft = "ocean"

        // Leaving and coming back keeps what was typed.
        await viewModel.reload()
        #expect(viewModel.draft == "ocean")

        // The next round has an empty field.
        let next = fixtures.moved(
            game,
            rounds: [fixtures.revealed(1, "ocean", "sushi", seen: true), fixtures.open(2)],
            version: 2
        )
        await env.cache.saveState(fixtures.state(current: next), ownerUserID: GameFixture.me)
        await viewModel.reload()
        #expect(viewModel.round?.roundNumber == 2)
        #expect(viewModel.draft.isEmpty)
    }

    @Test func aWordTheServerRefusedComesBackInTheField() async {
        let open = fixtures.open(1)
        let env = environment(fixtures.game(rounds: [open]))
        let viewModel = env.viewModel()
        await viewModel.reload()

        let refused = MindMeldRefusedWord(roundID: open.id, word: "ocean")
        await env.cache.recordRefusedWord(refused, ownerUserID: GameFixture.me)
        await viewModel.reload()

        #expect(viewModel.draft == "ocean")
        #expect(viewModel.notice == .moveRejected)
        // Shown once.
        viewModel.clearNotice()
        await viewModel.reload()
        #expect(viewModel.notice == nil)
    }

    @Test func aRefusedWordOfAnotherRoundOnlyShowsTheNotice() async {
        let env = environment(fixtures.game(rounds: [fixtures.open(1)]))
        let viewModel = env.viewModel()
        await viewModel.reload()

        let refused = MindMeldRefusedWord(roundID: UUID(), word: "ocean")
        await env.cache.recordRefusedWord(refused, ownerUserID: GameFixture.me)
        await viewModel.reload()

        #expect(viewModel.draft.isEmpty)
        #expect(viewModel.notice == .moveRejected)
    }

    // MARK: Surprise me

    @Test func surpriseMeFillsAWordNobodyUsedInTheGameLanguage() async {
        let game = fixtures.game(rounds: [fixtures.revealed(1, "pizza", "sushi"), fixtures.open(2)])
        let english = environment(game, overview: MindMeldTestEnvironment.overview(language: .en)).viewModel()
        await english.reload()
        let norwegian = environment(game, overview: MindMeldTestEnvironment.overview(language: .nb)).viewModel()
        await norwegian.reload()

        for _ in 0..<30 {
            english.surpriseMe()
            #expect(MindMeldStarterWords.english.contains(english.draft))
            #expect(english.draftIssue == nil)
            #expect(english.canLockIn)
            norwegian.surpriseMe()
            #expect(MindMeldStarterWords.norwegian.contains(norwegian.draft))
        }
    }

    @Test func surpriseMeNeverGivesTheWordAlreadyInTheField() async {
        let viewModel = environment(fixtures.game(rounds: [fixtures.open(1)])).viewModel()
        await viewModel.reload()

        for _ in 0..<30 {
            viewModel.draft = "pizza"
            viewModel.surpriseMe()
            #expect(MindMeldWord.matchKey(viewModel.draft) != "pizza")
        }
    }

    // MARK: The reveal

    @Test func countingANearMissMeldsTheGameOnThePhone() async throws {
        let near = fixtures.revealed(1, "ocean", "oceans", outcome: .near, seen: false)
        let env = environment(fixtures.game(rounds: [near, fixtures.open(2)]))
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .reveal)
        #expect(viewModel.revealOutcome == .near)
        #expect(viewModel.resolution.canCount)
        let identity = viewModel.revealIdentity

        viewModel.countIt()
        await viewModel.moveTask?.value

        #expect(viewModel.revealOutcome == .meld)
        #expect(viewModel.game?.state == .melded)
        #expect(!viewModel.resolution.canCount)
        #expect(viewModel.phase == .reveal)
        // The same reveal, so it does not play again.
        #expect(viewModel.revealIdentity == identity)
        let counts = await env.queued(.countMindMeldRound)
        #expect(try decodePayload(MindMeldCountPayload.self, counts.first).roundID == near.id)
    }

    @Test func countingIsOnlyOfferedForANearMiss() async {
        let game = fixtures.game(rounds: [fixtures.revealed(1, seen: false), fixtures.open(2)])
        let viewModel = environment(game).viewModel()
        await viewModel.reload()

        viewModel.countIt()
        await viewModel.moveTask?.value

        #expect(viewModel.revealOutcome == .miss)
        #expect(!viewModel.resolution.canCount)
    }

    @Test func continuingFromAMissMovesToTheNextRound() async throws {
        let first = fixtures.revealed(1, seen: false)
        let env = environment(fixtures.game(rounds: [first, fixtures.open(2)]))
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .reveal)
        #expect(viewModel.revealIdentity == "reveal-\(first.id.uuidString.lowercased())")

        viewModel.continueFromReveal()
        await viewModel.moveTask?.value

        #expect(viewModel.phase == .write)
        #expect(viewModel.round?.roundNumber == 2)
        #expect(viewModel.resolution.connectingPair?.mine == "ocean")
        let marks = await env.queued(.markMindMeldRevealSeen)
        let queuedEnds = await env.queued(.markMindMeldEndSeen)
        #expect(try decodePayload(MindMeldRevealSeenPayload.self, marks.first).roundID == first.id)
        #expect(queuedEnds.isEmpty)
    }

    @Test func continuingFromAFinishedGameMarksItsEndAndDoesNotStartAnother() async throws {
        let last = fixtures.revealed(2, "fish", "fish", outcome: .match, seen: false)
        let finished = fixtures.game(.melded, rounds: [fixtures.revealed(1), last])
        let env = environment(finished)
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .reveal)
        #expect(viewModel.revealOutcome == .meld)

        viewModel.continueFromReveal()
        await viewModel.moveTask?.value

        // The ending is seen, so the settled last round stays until "Play again".
        #expect(viewModel.phase == .over)
        let ends = await env.queued(.markMindMeldEndSeen)
        let reveals = await env.queued(.markMindMeldRevealSeen)
        #expect(try decodePayload(MindMeldEndSeenPayload.self, ends.first).gameID == finished.id)
        #expect(reveals.count == 1)
        #expect(env.gateway.starts == 0)
    }

    @Test func leavingARevealAfterItsVerdictMarksItSeen() async throws {
        let first = fixtures.revealed(1, seen: false)
        let env = environment(fixtures.game(rounds: [first, fixtures.open(2)]))
        let viewModel = env.viewModel()
        await viewModel.start()
        #expect(viewModel.phase == .reveal)

        viewModel.revealSettled()
        viewModel.stop()
        await viewModel.moveTask?.value

        let marks = await env.queued(.markMindMeldRevealSeen)
        #expect(try decodePayload(MindMeldRevealSeenPayload.self, marks.first).roundID == first.id)
    }

    @Test func leavingARevealBeforeItsVerdictKeepsItForNextTime() async {
        let env = environment(fixtures.game(rounds: [fixtures.revealed(1, seen: false), fixtures.open(2)]))
        let viewModel = env.viewModel()
        await viewModel.start()

        viewModel.stop()
        await viewModel.moveTask?.value

        let marks = await env.queued(.markMindMeldRevealSeen)
        #expect(marks.isEmpty)
    }

    @Test func continuingTwiceQueuesEachMarkOnce() async {
        let env = environment(fixtures.game(rounds: [fixtures.revealed(1, seen: false), fixtures.open(2)]))
        let viewModel = env.viewModel()
        await viewModel.reload()

        viewModel.continueFromReveal()
        viewModel.continueFromReveal()
        await viewModel.moveTask?.value

        let marks = await env.queued(.markMindMeldRevealSeen)
        #expect(marks.count == 1)
    }
}
