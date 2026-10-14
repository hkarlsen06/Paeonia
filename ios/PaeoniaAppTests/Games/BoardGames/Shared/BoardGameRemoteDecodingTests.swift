import Foundation
import Testing
@testable import PaeoniaApp

/// The board games' answers as the hosted backend sent them on 2026-10-14, with
/// the ids replaced. The app must decode them exactly, or the board never shows.
struct BoardGameRemoteDecodingTests {
    private static let games = #"""
    {
      "couple_id": "00000000-0000-0000-0000-0000000000c0", "data_epoch": "",
      "games": [
        {
          "draws": 0,
          "finished_at": null,
          "first_user_id": "00000000-0000-0000-0000-00000000000b",
          "game_number": 1,
          "games_finished": 0,
          "id": "00000000-0000-0000-0000-000000000100",
          "kind": "connect_four",
          "moves": [3],
          "my_wins": 0,
          "partner_wins": 0,
          "photo_media_asset_id": null,
          "previous": null,
          "stake": "Loser makes waffles",
          "stake_by_user_id": "00000000-0000-0000-0000-00000000000b",
          "started_at": "2026-10-14T01:12:40.569Z",
          "status": "playing",
          "turn_started_at": "2026-10-14T01:12:50.582Z",
          "turn_user_id": "00000000-0000-0000-0000-00000000000a",
          "updated_at": "2026-10-14T01:12:50.582Z",
          "version": 2,
          "win_line": [],
          "winner_user_id": null
        },
        {
          "draws": 0,
          "finished_at": "2026-10-14T01:13:35.921Z",
          "first_user_id": "00000000-0000-0000-0000-00000000000b",
          "game_number": 1,
          "games_finished": 1,
          "id": "00000000-0000-0000-0000-000000000101",
          "kind": "dots_and_boxes",
          "moves": [
            19, 23, 31, 25, 17, 16, 10, 33, 14, 12, 38, 28, 2, 22, 37, 6, 30, 3, 4, 26, 24, 13, 18, 1, 29,
            11, 5, 32, 20, 27, 7, 8, 35, 0, 9, 36, 39, 15, 34, 21
          ],
          "my_wins": 0,
          "partner_wins": 1,
          "photo_media_asset_id": "00000000-0000-0000-0000-0000000000f0",
          "previous": null,
          "stake": null,
          "stake_by_user_id": null,
          "started_at": "2026-10-14T01:12:40.922Z",
          "status": "finished",
          "turn_started_at": "2026-10-14T01:13:27.618Z",
          "turn_user_id": null,
          "updated_at": "2026-10-14T01:13:35.921Z",
          "version": 41,
          "win_line": [3, 4, 5, 6, 7, 8, 9, 12, 13],
          "winner_user_id": "00000000-0000-0000-0000-00000000000b"
        },
        {
          "draws": 0,
          "finished_at": "2026-10-14T01:16:31.015Z",
          "first_user_id": "00000000-0000-0000-0000-00000000000b",
          "game_number": 1,
          "games_finished": 1,
          "id": "00000000-0000-0000-0000-000000000102",
          "kind": "ultimate_tic_tac_toe",
          "moves": [
            3, 31, 37, 14, 48, 29, 19, 15, 55, 12, 35, 78, 54, 4, 36, 8, 76, 40, 41, 52, 69, 62, 74, 26,
            77, 53, 75, 27, 7, 66, 30, 34, 63, 6, 60, 58, 39, 28, 9, 5, 47, 21, 20, 22, 44, 10, 13, 42, 59,
            46, 16, 64, 11, 24, 61, 70, 68, 45, 1, 17, 2, 25, 71, 50, 51, 57, 67, 43, 0, 49, 38
          ],
          "my_wins": 0,
          "partner_wins": 1,
          "photo_media_asset_id": null,
          "previous": null,
          "stake": null,
          "stake_by_user_id": null,
          "started_at": "2026-10-14T01:12:41.329Z",
          "status": "finished",
          "turn_started_at": "2026-10-14T01:16:26.829Z",
          "turn_user_id": null,
          "updated_at": "2026-10-14T01:16:31.015Z",
          "version": 72,
          "win_line": [0, 4, 8],
          "winner_user_id": "00000000-0000-0000-0000-00000000000b"
        }
      ],
      "partner_user_id": "00000000-0000-0000-0000-00000000000b",
      "user_id": "00000000-0000-0000-0000-00000000000a"
    }
    """#

    private static let marks = #"""
    {
      "user_id": "00000000-0000-0000-0000-00000000000a",
      "mine": {
        "drawing": "AAEC",
        "updated_at": "2026-10-14T01:20:00.000Z"
      },
      "partner": null
    }
    """#

    @Test func theServersBoardGamesDecodeAndReplay() throws {
        let state = try PaeoniaConvexClient.decoder.decode(RemoteBoardGames.self, from: Data(Self.games.utf8))

        #expect(state.games.map(\.kind) == [.connectFour, .dotsAndBoxes, .ultimateTicTacToe])
        let connectFour = try #require(state.game(.connectFour))
        #expect(connectFour.status == .playing)
        #expect(connectFour.moves == [3])
        #expect(connectFour.stake == "Loser makes waffles")
        #expect(connectFour.turnUserID == state.userID)
        #expect(connectFour.finishedAt == nil)

        let dotsAndBoxes = try #require(state.game(.dotsAndBoxes))
        #expect(dotsAndBoxes.status == .finished)
        #expect(dotsAndBoxes.photoMediaAssetID != nil)
        let board = try #require(DotsAndBoxesBoard.replay(dotsAndBoxes.moves))
        #expect(board.outcome?.line == dotsAndBoxes.winLine)
        #expect(dotsAndBoxes.winnerUserID == state.partnerUserID)

        let ultimate = try #require(state.game(.ultimateTicTacToe))
        let replayed = try #require(UltimateTicTacToeBoard.replay(ultimate.moves))
        #expect(replayed.outcome?.line == ultimate.winLine)
    }

    @Test func theServersMarksDecode() throws {
        let marks = try PaeoniaConvexClient.decoder.decode(RemoteBoardGameMarks.self, from: Data(Self.marks.utf8))

        #expect(marks.mine?.drawing == "AAEC")
        #expect(marks.partner == nil)
    }
}
