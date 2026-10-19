import Foundation
import Testing
@testable import PaeoniaApp

/// The JSON `exquisiteCorpse:get_exquisite_corpse` and its siblings return.
struct ExquisiteCorpseRemoteModelsTests {
    private let stateJSON = """
    {
      "user_id": "11111111-1111-4111-8111-111111111111",
      "partner_user_id": "22222222-2222-4222-8222-222222222222",
      "couple_id": "33333333-3333-4333-8333-333333333333", "data_epoch": "",
      "game": {
        "id": "44444444-4444-4444-8444-444444444444",
        "turn_user_id": "11111111-1111-4111-8111-111111111111",
        "turn_started_at": "2026-10-13T10:00:00.123Z",
        "figure_id": "55555555-5555-4555-8555-555555555555",
        "figure_number": 3,
        "part_index": 1,
        "figures_finished": 2,
        "version": 9,
        "created_at": "2026-10-01T08:00:00.000Z",
        "updated_at": "2026-10-13T10:00:00.123Z"
      },
      "current_figure": {
        "id": "55555555-5555-4555-8555-555555555555",
        "number": 3,
        "starter_user_id": "22222222-2222-4222-8222-222222222222",
        "created_at": "2026-10-13T09:00:00.000Z",
        "finished_at": null,
        "my_reveal_seen_at": null,
        "starred_by_me": false,
        "parts": [
          {
            "id": "66666666-6666-4666-8666-666666666666",
            "part_index": 0,
            "drawer_user_id": "22222222-2222-4222-8222-222222222222",
            "created_at": "2026-10-13T09:00:00.000Z",
            "strip_media_asset_id": "77777777-7777-4777-8777-777777777777",
            "drawing_media_asset_id": null,
            "idea": null
          }
        ]
      },
      "recent_figures": [
        {
          "id": "88888888-8888-4888-8888-888888888888",
          "number": 2,
          "starter_user_id": "11111111-1111-4111-8111-111111111111",
          "created_at": "2026-10-12T09:00:00.000Z",
          "finished_at": "2026-10-12T09:30:00.000Z",
          "my_reveal_seen_at": "2026-10-12T10:00:00Z",
          "starred_by_me": true,
          "parts": [
            {
              "id": "99999999-9999-4999-8999-999999999999",
              "part_index": 2,
              "drawer_user_id": "11111111-1111-4111-8111-111111111111",
              "created_at": "2026-10-12T09:30:00.000Z",
              "strip_media_asset_id": null,
              "drawing_media_asset_id": "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
              "idea": { "id": "legs-frog-legs", "text": "frog legs" }
            }
          ]
        }
      ],
      "ideas": [
        { "id": "body-teapot", "text": "a teapot" },
        { "id": "body-robot", "text": "a robot" }
      ]
    }
    """

    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try PaeoniaConvexClient.decoder.decode(type, from: Data(json.utf8))
    }

    @Test func decodesTheQueryAsTheServerSendsIt() throws {
        let state = try decode(RemoteExquisiteCorpseState.self, stateJSON)

        #expect(state.userID == UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        #expect(state.partnerUserID == UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        let game = try #require(state.game)
        #expect(game.figureNumber == 3 && game.partIndex == 1 && game.figuresFinished == 2 && game.version == 9)
        #expect(game.figureID == UUID(uuidString: "55555555-5555-4555-8555-555555555555"))
        #expect(game.turnUserID == state.userID)
        #expect(abs(game.turnStartedAt.timeIntervalSince1970 - 1_791_885_600.123) < 0.001)

        let current = try #require(state.currentFigure)
        #expect(current.id == game.figureID)
        #expect(!current.isFinished)
        #expect(current.part(at: 0)?.stripMediaAssetID == UUID(uuidString: "77777777-7777-4777-8777-777777777777"))
        #expect(current.part(at: 0)?.drawingMediaAssetID == nil)
        #expect(current.part(at: 0)?.idea == nil)
        #expect(current.part(at: 1) == nil)

        let finished = try #require(state.recentFigures.first)
        #expect(finished.isFinished)
        #expect(finished.starredByMe)
        #expect(finished.myRevealSeenAt != nil)
        let legs = try #require(finished.part(at: 2))
        #expect(legs.kind == .legs)
        #expect(legs.stripMediaAssetID == nil)
        #expect(legs.idea == RemoteExquisiteCorpseIdea(id: "legs-frog-legs", text: "frog legs"))

        #expect(state.ideas.map(\.text) == ["a teapot", "a robot"])
    }

    @Test func decodesAStateWithoutAGameOrAPartner() throws {
        let json = """
        {
          "user_id": "11111111-1111-4111-8111-111111111111",
          "partner_user_id": null,
          "couple_id": "33333333-3333-4333-8333-333333333333", "data_epoch": "",
          "game": null,
          "current_figure": null,
          "recent_figures": [],
          "ideas": []
        }
        """

        let state = try decode(RemoteExquisiteCorpseState.self, json)

        #expect(state.partnerUserID == nil && state.game == nil && state.currentFigure == nil)
        #expect(state.recentFigures.isEmpty && state.ideas.isEmpty)
    }

    @Test func decodesAHistoryPage() throws {
        let figure = """
        {
          "id": "88888888-8888-4888-8888-888888888888", "number": 2,
          "starter_user_id": "11111111-1111-4111-8111-111111111111",
          "created_at": "2026-10-12T09:00:00.000Z", "finished_at": "2026-10-12T09:30:00.000Z",
          "my_reveal_seen_at": null, "starred_by_me": false, "parts": []
        }
        """

        let more = try decode(
            RemoteExquisiteCorpseHistoryPage.self,
            #"{"figures": [\#(figure)], "next_before_figure_number": 2}"#
        )
        let lastJSON = #"{"figures": [], "next_before_figure_number": null}"#
        let last = try decode(RemoteExquisiteCorpseHistoryPage.self, lastJSON)
        let cached = try PaeoniaConvexClient.encoder.encode(more)

        #expect(more.figures.map(\.number) == [2])
        #expect(more.nextBeforeFigureNumber == 2)
        #expect(last.figures.isEmpty && last.nextBeforeFigureNumber == nil)
        #expect(try PaeoniaConvexClient.decoder.decode(RemoteExquisiteCorpseHistoryPage.self, from: cached) == more)
    }

    @Test func decodesTheResultOfSendingAPart() throws {
        let json = """
        {
          "figure_id": "55555555-5555-4555-8555-555555555555",
          "part_id": "66666666-6666-4666-8666-666666666666",
          "part_index": 2,
          "figure_finished": true,
          "created_at": "2026-10-13T10:00:00.000Z"
        }
        """

        let result = try decode(RemoteExquisiteCorpseSubmitPartResult.self, json)

        #expect(result.partIndex == 2 && result.figureFinished)
        #expect(result.partID == UUID(uuidString: "66666666-6666-4666-8666-666666666666"))
        #expect(result.figureID == UUID(uuidString: "55555555-5555-4555-8555-555555555555"))
    }
}
