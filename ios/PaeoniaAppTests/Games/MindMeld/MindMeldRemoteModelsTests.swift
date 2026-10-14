import Foundation
import Testing
@testable import PaeoniaApp

/// What the server's JSON means for the Mind Meld models.
struct MindMeldRemoteModelsTests {
    private static let me = "11111111-1111-1111-1111-111111111111"
    private static let partner = "22222222-2222-2222-2222-222222222222"

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try PaeoniaConvexClient.decoder.decode(type, from: Data(json.utf8))
    }

    /// `mindMeld:get_mind_meld` with a game in play and a game the partner ended.
    private func stateJSON(gameNumber: Int = 2, version: Int = 5) -> String {
        """
        {"user_id":"\(Self.me)","partner_user_id":"\(Self.partner)",
         "couple_id":"33333333-3333-3333-3333-333333333333",
         "data_epoch":"",
         "current":{"id":"aaaaaaaa-0000-4000-8000-000000000002","game_number":\(gameNumber),"state":"playing",
           "end_reason":null,"ended_by_user_id":null,"ended_at":null,"max_rounds":10,"my_end_seen_at":null,
           "meld_number":null,"is_record":false,"created_by_user_id":"\(Self.partner)",
           "created_at":"2026-10-12T10:00:00.000Z","updated_at":"2026-10-12T10:05:00.500Z","version":\(version),
           "rounds":[
             {"id":"bbbbbbbb-0000-4000-8000-000000000001","round_number":1,"state":"revealed","outcome":"near",
              "counted_by_user_id":null,"my_word":"ocean","my_locked_at":"2026-10-12T10:01:00.250Z",
              "partner_locked":true,"partner_locked_at":"2026-10-12T10:02:00.000Z","partner_word":"oceans",
              "revealed_at":"2026-10-12T10:02:00.000Z","my_reveal_seen_at":"2026-10-12T10:02:03.125Z"},
             {"id":"bbbbbbbb-0000-4000-8000-000000000002","round_number":2,"state":"open","outcome":null,
              "counted_by_user_id":null,"my_word":null,"my_locked_at":null,"partner_locked":true,
              "partner_locked_at":"2026-10-12T10:05:00.500Z","partner_word":null,"revealed_at":null,
              "my_reveal_seen_at":null}]},
         "previous":{"id":"aaaaaaaa-0000-4000-8000-000000000001","game_number":1,"state":"ended",
           "end_reason":"restart","ended_by_user_id":"\(Self.partner)","ended_at":"2026-10-12T09:59:00.000Z",
           "max_rounds":10,"my_end_seen_at":null,"meld_number":null,"is_record":false,
           "created_by_user_id":"\(Self.me)","created_at":"2026-10-12T09:00:00.000Z",
           "updated_at":"2026-10-12T09:59:00.000Z","version":9,"rounds":[]},
         "stats":{"melds":3,"fewest_rounds":2,"games":5}}
        """
    }

    @Test func decodesTheMindMeldQueryAsTheServerSendsIt() throws {
        let state = try decode(RemoteMindMeldState.self, stateJSON())

        #expect(state.userID == UUID(uuidString: Self.me))
        #expect(state.partnerUserID == UUID(uuidString: Self.partner))
        #expect(state.stats == RemoteMindMeldStats(melds: 3, fewestRounds: 2, games: 5))

        let game = try #require(state.current)
        #expect(game.gameNumber == 2 && game.version == 5 && game.maxRounds == 10)
        #expect(game.state == .playing)
        #expect(game.endReason == nil && game.endedAt == nil && game.myEndSeenAt == nil)
        #expect(!game.isRecord && game.meldNumber == nil)
        #expect(game.rounds.map(\.roundNumber) == [1, 2])

        let revealed = game.rounds[0]
        #expect(revealed.state == .revealed && revealed.outcome == .near)
        #expect(revealed.myWord == "ocean" && revealed.partnerWord == "oceans")
        #expect(revealed.myRevealSeenAt != nil && revealed.countedByUserID == nil)
        // Fractional seconds survive.
        let lockedAt = try #require(revealed.myLockedAt).timeIntervalSince1970
        #expect(abs(lockedAt.truncatingRemainder(dividingBy: 1) - 0.25) < 0.001)

        let open = game.rounds[1]
        #expect(open.state == .open && open.outcome == nil)
        #expect(open.myWord == nil && open.partnerWord == nil && open.partnerLocked)

        let previous = try #require(state.previous)
        #expect(previous.state == .ended && previous.endReason == .restart)
        #expect(previous.endedByUserID == UUID(uuidString: Self.partner))
        #expect(previous.endedAt != nil)
    }

    @Test func decodesACoupleWithNoGame() throws {
        let json = """
        {"user_id":"\(Self.me)","partner_user_id":null,"couple_id":"33333333-3333-3333-3333-333333333333",
         "data_epoch":"",
         "current":null,"previous":null,"stats":{"melds":0,"fewest_rounds":null,"games":0}}
        """
        let state = try decode(RemoteMindMeldState.self, json)

        #expect(state.partnerUserID == nil && state.current == nil && state.previous == nil)
        #expect(state.stats.fewestRounds == nil)
    }

    @Test func decodesAMeldedGameWithACountedRound() throws {
        let json = """
        {"id":"aaaaaaaa-0000-4000-8000-000000000003","game_number":3,"state":"melded","end_reason":null,
         "ended_by_user_id":null,"ended_at":"2026-10-12T11:00:00.000Z","max_rounds":10,
         "my_end_seen_at":"2026-10-12T11:00:05.000Z","meld_number":4,"is_record":true,
         "created_by_user_id":"\(Self.me)","created_at":"2026-10-12T10:30:00.000Z",
         "updated_at":"2026-10-12T11:00:00.000Z","version":8,
         "rounds":[{"id":"bbbbbbbb-0000-4000-8000-000000000009","round_number":1,"state":"revealed",
           "outcome":"near","counted_by_user_id":"\(Self.partner)","my_word":"dog","my_locked_at":null,
           "partner_locked":true,"partner_locked_at":null,"partner_word":"dogs","revealed_at":null,
           "my_reveal_seen_at":null}]}
        """
        let game = try decode(RemoteMindMeldGame.self, json)

        #expect(game.state == .melded && game.isFinished)
        #expect(game.meldNumber == 4 && game.isRecord)
        #expect(game.rounds.first?.countedByUserID == UUID(uuidString: Self.partner))
    }

    @Test func decodesAHistoryPage() throws {
        let json = """
        {"games":[
          {"id":"aaaaaaaa-0000-4000-8000-000000000003","game_number":3,"state":"melded","end_reason":null,
           "ended_by_user_id":null,"created_at":"2026-10-12T10:30:00.000Z","ended_at":"2026-10-12T11:00:00.000Z",
           "meld_number":4,"rounds":[
             {"round_number":1,"my_word":"ocean","partner_word":"sushi","outcome":"miss","counted_by_user_id":null},
             {"round_number":2,"my_word":"fish","partner_word":"fish","outcome":"match","counted_by_user_id":null}]},
          {"id":"aaaaaaaa-0000-4000-8000-000000000002","game_number":2,"state":"ended","end_reason":"restart",
           "ended_by_user_id":"\(Self.partner)","created_at":"2026-10-12T10:00:00.000Z",
           "ended_at":"2026-10-12T10:20:00.000Z","meld_number":null,"rounds":[]}],
         "next_before_game_number":2,"stats":{"melds":4,"fewest_rounds":2,"games":6}}
        """
        let page = try decode(RemoteMindMeldHistoryPage.self, json)

        #expect(page.games.map(\.gameNumber) == [3, 2])
        #expect(page.nextBeforeGameNumber == 2)
        #expect(page.stats.melds == 4)
        #expect(page.games[0].rounds.map(\.outcome) == [.miss, .match])
        #expect(page.games[0].rounds.map(\.id) == [1, 2])
        #expect(page.games[1].endReason == .restart && page.games[1].meldNumber == nil)
    }

    @Test func decodesTheMutationResults() throws {
        let round = "bbbbbbbb-0000-4000-8000-000000000001"
        let game = "aaaaaaaa-0000-4000-8000-000000000001"

        let lock = try decode(RemoteMindMeldLockResult.self, """
        {"round_id":"\(round)","round_state":"revealed","outcome":"match","game_state":"melded",
         "locked_at":"2026-10-12T10:00:00.000Z"}
        """)
        #expect(lock.roundState == .revealed && lock.outcome == .match && lock.gameState == .melded)

        let firstLock = try decode(RemoteMindMeldLockResult.self, """
        {"round_id":"\(round)","round_state":"open","outcome":null,"game_state":"playing",
         "locked_at":"2026-10-12T10:00:00.000Z"}
        """)
        #expect(firstLock.roundState == .open && firstLock.outcome == nil)

        let count = try decode(RemoteMindMeldCountResult.self, """
        {"round_id":"\(round)","game_id":"\(game)","game_state":"melded"}
        """)
        #expect(count.gameState == .melded && count.gameID == UUID(uuidString: game))

        let seen = try decode(RemoteMindMeldRevealSeenResult.self, """
        {"round_id":"\(round)","reveal_seen_at":"2026-10-12T10:00:00.000Z"}
        """)
        #expect(seen.roundID == UUID(uuidString: round))

        let end = try decode(RemoteMindMeldEndSeenResult.self, """
        {"game_id":"\(game)","end_seen_at":"2026-10-12T10:00:00.000Z"}
        """)
        #expect(end.gameID == UUID(uuidString: game))

        let start = try decode(RemoteMindMeldStartResult.self, """
        {"game_id":"\(game)","created":true}
        """)
        #expect(start.created)
    }

    // MARK: Order

    @Test func aStateWithALowerGameNumberOrAnOlderVersionIsOlder() throws {
        let base = try decode(RemoteMindMeldState.self, stateJSON(gameNumber: 2, version: 5))
        let newerVersion = try decode(RemoteMindMeldState.self, stateJSON(gameNumber: 2, version: 6))
        let nextGame = try decode(RemoteMindMeldState.self, stateJSON(gameNumber: 3, version: 1))

        #expect(base.isOlder(than: newerVersion))
        #expect(!newerVersion.isOlder(than: base))
        #expect(!base.isOlder(than: base))
        // A later game wins whatever its version.
        #expect(base.isOlder(than: nextGame))
        #expect(!nextGame.isOlder(than: base))
        // Game numbers of another couple say nothing about this one.
        let otherCouple = try decode(RemoteMindMeldState.self, stateJSON(gameNumber: 9).replacingOccurrences(
            of: "33333333-3333-3333-3333-333333333333",
            with: "44444444-4444-4444-4444-444444444444"
        ))
        #expect(!base.isOlder(than: otherCouple))
        #expect(!otherCouple.isOlder(than: base))
    }

    @Test func aStateWithoutAGameIsOlderOnlyThanTheSameCouplesGame() throws {
        let base = try decode(RemoteMindMeldState.self, stateJSON())
        let empty = try decode(RemoteMindMeldState.self, """
        {"user_id":"\(Self.me)","partner_user_id":null,"couple_id":"33333333-3333-3333-3333-333333333333",
         "data_epoch":"",
         "current":null,"previous":null,"stats":{"melds":0,"fewest_rounds":null,"games":0}}
        """)
        let otherJSON = stateJSON(gameNumber: 9)
            .replacingOccurrences(of: "\"user_id\":\"\(Self.me)\"", with: "\"user_id\":\"\(Self.partner)\"")
        let other = try decode(RemoteMindMeldState.self, otherJSON)

        let otherCouple = try decode(RemoteMindMeldState.self, """
        {"user_id":"\(Self.me)","partner_user_id":null,"couple_id":"44444444-4444-4444-4444-444444444444",
         "data_epoch":"",
         "current":null,"previous":null,"stats":{"melds":0,"fewest_rounds":null,"games":0}}
        """)
        let restored = try decode(RemoteMindMeldState.self, """
        {"user_id":"\(Self.me)","partner_user_id":null,"couple_id":"33333333-3333-3333-3333-333333333333",
         "data_epoch":"restored",
         "current":null,"previous":null,"stats":{"melds":0,"fewest_rounds":null,"games":0}}
        """)

        // A late read from before the first game must not wipe the game out.
        #expect(empty.isOlder(than: base))
        #expect(!base.isOlder(than: empty))
        // A new couple starts with no game, and that is not behind the old couple's.
        #expect(!otherCouple.isOlder(than: base))
        #expect(!base.isOlder(than: other))
        // After a restore of the server, its state wins even without the game.
        #expect(!restored.isOlder(than: base))
    }
}
