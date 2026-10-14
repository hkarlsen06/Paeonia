import Foundation
import Testing
@testable import PaeoniaApp

/// What the server's JSON means, and the live message on the relay.
struct StoryChainContractTests {
    private typealias Fixture = StoryChainFixture

    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try PaeoniaConvexClient.decoder.decode(type, from: Data(json.utf8))
    }

    private static let stateJSON = """
    {"user_id":"11111111-1111-4111-8111-111111111111",
     "partner_user_id":"22222222-2222-4222-8222-222222222222",
     "couple_id":"33333333-3333-4333-8333-333333333333","data_epoch":"",
     "game":{"id":"aaaaaaaa-0000-4000-8000-000000000001","state":"writing",
       "turn_user_id":"11111111-1111-4111-8111-111111111111","turn_number":6,
       "current_story_id":"bbbbbbbb-0000-4000-8000-000000000002","story_count":2,"finished_count":1,
       "turn_started_at":"2026-10-13T10:00:00.000Z","version":9},
     "current_story":{"id":"bbbbbbbb-0000-4000-8000-000000000002","story_number":2,
       "starter_user_id":"22222222-2222-4222-8222-222222222222",
       "opening_id":"en-key","opening_text":"A key that opened nothing in town.",
       "state":"writing",
       "lines":[
         {"id":"cccccccc-0000-4000-8000-000000000001","number":1,
          "author_user_id":"22222222-2222-4222-8222-222222222222",
          "text":"So she took the night bus to the coast.","dare_word":"anchor",
          "created_at":"2026-10-13T09:00:00.000Z"},
         {"id":"cccccccc-0000-4000-8000-000000000002","number":2,
          "author_user_id":"11111111-1111-4111-8111-111111111111",
          "text":"An anchor hung on the door of the last house.","dare_word":null,
          "created_at":"2026-10-13T09:30:00.500Z"}],
       "last_line_user_id":null,"title":null,"titled_by_user_id":null,"finished_at":null,
       "seen_by_me":false,"starred_by_me":false,
       "created_at":"2026-10-13T08:00:00.000Z","updated_at":"2026-10-13T09:30:00.500Z"},
     "previous_story":{"id":"bbbbbbbb-0000-4000-8000-000000000001","story_number":1,
       "starter_user_id":"11111111-1111-4111-8111-111111111111",
       "opening_id":null,"opening_text":null,"state":"finished","lines":[],
       "last_line_user_id":"22222222-2222-4222-8222-222222222222","title":"The night bus",
       "titled_by_user_id":"11111111-1111-4111-8111-111111111111",
       "finished_at":"2026-10-12T20:00:00.000Z","seen_by_me":true,"starred_by_me":true,
       "created_at":"2026-10-10T08:00:00.000Z","updated_at":"2026-10-12T20:00:00.000Z"},
     "opening_choices":null,
     "word_choices":[{"word_id":"en-lighthouse","word":"lighthouse"},{"word_id":"en-ladder","word":"ladder"}]}
    """

    @Test func decodesTheStateAsTheServerSendsIt() throws {
        let state = try decode(RemoteStoryChainState.self, Self.stateJSON)

        #expect(state.userID == Fixture.me)
        #expect(state.partnerUserID == Fixture.partner)
        #expect(state.coupleID == Fixture.couple)
        #expect(state.game?.state == .writing)
        #expect(state.game?.turnUserID == Fixture.me)
        #expect(state.game?.currentStoryID == Fixture.nextStoryID)
        #expect(state.game?.storyCount == 2)
        #expect(state.game?.finishedCount == 1)
        #expect(state.game?.version == 9)
        #expect(state.openingChoices == nil)
        #expect(state.wordChoices?.map(\.word) == ["lighthouse", "ladder"])
        #expect(state.wordChoices?.first?.wordID == "en-lighthouse")
    }

    @Test func decodesTheCurrentStoryWithItsLinesAndDares() throws {
        let state = try decode(RemoteStoryChainState.self, Self.stateJSON)
        let current = try #require(state.currentStory)

        #expect(current.storyNumber == 2)
        #expect(current.starterUserID == Fixture.partner)
        #expect(current.openingID == "en-key")
        #expect(current.openingText == "A key that opened nothing in town.")
        #expect(current.state == .writing)
        #expect(current.lines.map(\.number) == [1, 2])
        #expect(current.lines.map(\.authorUserID) == [Fixture.partner, Fixture.me])
        #expect(current.lines.map(\.dareWord) == ["anchor", nil])
        #expect(current.lastLineUserID == nil)
        #expect(current.title == nil)
        #expect(current.finishedAt == nil)
        #expect(!current.seenByMe)
        #expect(!current.starredByMe)
    }

    @Test func decodesTheFinishedPreviousStory() throws {
        let state = try decode(RemoteStoryChainState.self, Self.stateJSON)
        let previous = try #require(state.previousStory)

        #expect(previous.state == .finished)
        #expect(previous.title == "The night bus")
        #expect(previous.titledByUserID == Fixture.me)
        #expect(previous.lastLineUserID == Fixture.partner)
        #expect(previous.finishedAt != nil)
        #expect(previous.openingID == nil)
        #expect(previous.openingText == nil)
        #expect(previous.seenByMe)
        #expect(previous.starredByMe)
    }

    @Test func decodesAStateBeforeTheFirstStoryWithItsOpeningChoices() throws {
        let json = """
        {"user_id":"11111111-1111-4111-8111-111111111111","partner_user_id":null,
         "couple_id":"33333333-3333-4333-8333-333333333333","data_epoch":"",
         "game":{"id":"aaaaaaaa-0000-4000-8000-000000000001","state":"choosing_opening",
           "turn_user_id":"11111111-1111-4111-8111-111111111111","turn_number":1,
           "current_story_id":null,"story_count":0,"finished_count":0,
           "turn_started_at":"2026-10-13T10:00:00Z","version":1},
         "current_story":null,"previous_story":null,
         "opening_choices":[{"opening_id":"en-key","text":"A key that opened nothing in town."}],
         "word_choices":null}
        """
        let state = try decode(RemoteStoryChainState.self, json)

        #expect(state.partnerUserID == nil)
        #expect(state.game?.state == .choosingOpening)
        #expect(state.game?.currentStoryID == nil)
        #expect(state.currentStory == nil)
        #expect(state.previousStory == nil)
        #expect(state.openingChoices?.map(\.openingID) == ["en-key"])
        #expect(state.openingChoices?.first?.text == "A key that opened nothing in town.")
        #expect(state.wordChoices == nil)
    }

    @Test func decodesAStateWithoutAGame() throws {
        let json = """
        {"user_id":"11111111-1111-4111-8111-111111111111","partner_user_id":null,
         "couple_id":"33333333-3333-4333-8333-333333333333","data_epoch":"","game":null,
         "current_story":null,"previous_story":null,"opening_choices":null,"word_choices":null}
        """
        let state = try decode(RemoteStoryChainState.self, json)

        #expect(state.game == nil)
    }

    @Test func decodesAHistoryPage() throws {
        let json = """
        {"stories":[
          {"id":"bbbbbbbb-0000-4000-8000-000000000002","story_number":2,"title":"The night bus",
           "first_line":"A key that opened nothing in town.","line_count":14,
           "finished_at":"2026-10-12T20:00:00.000Z","starred_by_me":true},
          {"id":"bbbbbbbb-0000-4000-8000-000000000001","story_number":1,"title":"Anchors",
           "first_line":"It began with a ladder.","line_count":9,
           "finished_at":"2026-10-10T20:00:00.000Z","starred_by_me":false}],
         "next_before_story_number":1}
        """
        let page = try decode(RemoteStoryChainHistoryPage.self, json)

        #expect(page.stories.map(\.title) == ["The night bus", "Anchors"])
        #expect(page.stories.map(\.lineCount) == [14, 9])
        #expect(page.stories.map(\.starredByMe) == [true, false])
        #expect(page.stories.first?.firstLine == "A key that opened nothing in town.")
        #expect(page.nextBeforeStoryNumber == 1)

        let last = try decode(RemoteStoryChainHistoryPage.self, #"{"stories":[],"next_before_story_number":null}"#)
        #expect(last.stories.isEmpty)
        #expect(last.nextBeforeStoryNumber == nil)
    }

    @Test func decodesTheMutationResults() throws {
        let story = "bbbbbbbb-0000-4000-8000-000000000002"
        let start = try decode(RemoteStartStoryResult.self, #"{"story_id":"\#(story)","story_number":3}"#)
        let line = try decode(
            RemoteAddStoryLineResult.self,
            #"{"line_id":"cccccccc-0000-4000-8000-000000000002","number":8,"story_state":"titling"}"#
        )
        let name = try decode(RemoteNameStoryResult.self, #"{"story_id":"\#(story)","title":"The night bus"}"#)
        let star = try decode(RemoteStoryStarResult.self, #"{"story_id":"\#(story)","starred":true}"#)
        let ensure = try decode(
            RemoteEnsureGameResult.self,
            #"{"game_id":"aaaaaaaa-0000-4000-8000-000000000001","created":true}"#
        )

        #expect(start.storyID == Fixture.nextStoryID)
        #expect(start.storyNumber == 3)
        #expect(line.number == 8)
        #expect(line.storyState == .titling)
        #expect(name.title == "The night bus")
        #expect(star.starred)
        #expect(ensure.gameID == Fixture.gameID)
        #expect(ensure.created)
    }

    // MARK: Never older

    @Test func aStateIsOlderOnlyForTheSameGameWithALowerVersion() {
        func state(version: Int, game: UUID = Fixture.gameID, user: UUID = Fixture.me) -> RemoteStoryChainState {
            Fixture.state(Fixture.game(.writing, turn: Fixture.me, version: version, id: game), userID: user)
        }
        let low = state(version: 4)

        #expect(low.isOlder(than: state(version: 5)))
        #expect(!state(version: 5).isOlder(than: low))
        #expect(!low.isOlder(than: low))
        #expect(!low.isOlder(than: state(version: 9, game: UUID())))
        #expect(!low.isOlder(than: state(version: 9, user: UUID())))
        #expect(!low.isOlder(than: Fixture.state(nil)))
        #expect(!Fixture.state(nil).isOlder(than: low))
    }

    // MARK: Live message

    @Test func theLiveMessageUsesShortKeysAndLeavesOutALineThatIsNotSentYet() throws {
        let message = StoryChainLiveMessage(story: Fixture.storyID, number: 4, text: "Once upon", isLast: true)
        let data = try JSONEncoder().encode(GameLiveEnvelope(game: StoryChainLiveMessage.game, message: message))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let inner = try #require(object["message"] as? [String: Any])

        #expect(StoryChainLiveMessage.game == "story_chain")
        #expect(object["game"] as? String == "story_chain")
        #expect(Set(inner.keys) == ["story", "number", "text", "last", "sent"])
        #expect(inner["last"] as? Bool == true)
        #expect(inner["sent"] as? Bool == false)
        #expect(inner["number"] as? Int == 4)
        #expect(inner["text"] as? String == "Once upon")
    }

    @Test func aSentLiveMessageCarriesTheLineAndSurvivesTheRelay() throws {
        let lineID = UUID()
        let message = StoryChainLiveMessage(
            story: Fixture.storyID,
            number: 2,
            text: "A whole line.",
            isLast: false,
            lineID: lineID,
            sent: true
        )

        let data = try JSONEncoder().encode(GameLiveEnvelope(game: StoryChainLiveMessage.game, message: message))
        let decoded = try JSONDecoder().decode(GameLiveEnvelope<StoryChainLiveMessage>.self, from: data)

        #expect(decoded.game == "story_chain")
        #expect(decoded.message == message)
        #expect(decoded.message.lineID == lineID)
        #expect(decoded.message.sent)
    }

    @Test func aLiveDraftLongerThanTheLineLimitIsCutOnTheWayInAndOut() throws {
        let long = String(repeating: "a", count: 300)
        let made = StoryChainLiveMessage(story: Fixture.storyID, number: 1, text: long, isLast: false)
        let json = """
        {"story":"\(Fixture.storyID.uuidString)","number":1,"text":"\(long)","last":false,"sent":false}
        """
        let received = try JSONDecoder().decode(StoryChainLiveMessage.self, from: Data(json.utf8))

        #expect(made.text.unicodeScalars.count == 240)
        #expect(received.text.unicodeScalars.count == 240)
        #expect(received.lineID == nil)
    }
}
