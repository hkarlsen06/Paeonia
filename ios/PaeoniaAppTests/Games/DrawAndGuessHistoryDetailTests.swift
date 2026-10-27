import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// The history answers the server sends.
struct DrawAndGuessHistoryDetailTests {
    @Test func theServersAnswersDecode() throws {
        let page = """
        {"rounds":[{"id":"bbbbbbbb-0000-4000-8000-000000000001","round_number":7,
        "drawer_user_id":"aaaaaaaa-0000-4000-8000-000000000001",
        "guesser_user_id":"aaaaaaaa-0000-4000-8000-000000000002","word":"cat","difficulty":"easy",
        "points":1,"state":"solved","drawing_media_asset_id":"cccccccc-0000-4000-8000-000000000001",
        "solve_ms":7500,"speed_bonus":2,"first_try_bonus":1,"hints_used":0,"attempt_count":1,
        "personal_best":true,"guesses":["cat"],
        "started_at":"2026-10-12T08:00:00.000Z","ended_at":"2026-10-12T08:01:00.000Z"}],
        "next_before_round_number":null}
        """
        let decoded = try PaeoniaConvexClient.decoder.decode(RemoteDrawAndGuessHistoryPage.self, from: Data(page.utf8))
        #expect(decoded.rounds.first?.solveMs == 7_500)
        #expect(decoded.rounds.first?.guesses == ["cat"])
        #expect(decoded.nextBeforeRoundNumber == nil)

        let records = """
        {"partners":[{"user_id":"aaaaaaaa-0000-4000-8000-000000000001","solves":0,"first_try_solves":0,
        "average_solve_ms":null,"fastest_solve_ms":null,"fastest_solve_word":null,"drawings_solved":0}]}
        """
        let decodedRecords = try PaeoniaConvexClient.decoder.decode(
            RemoteDrawAndGuessRecords.self,
            from: Data(records.utf8)
        )
        #expect(decodedRecords.partners.first?.averageSolveMs == nil)
    }
}
