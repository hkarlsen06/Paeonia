import Foundation
import Testing
@testable import PaeoniaApp

/// Scoring, the topic rules and how a state is ordered.
struct ConsensioRulesTests {
    @Test func pointsDropByOneEveryFourOffAsOnTheServer() {
        let distances = [0, 3, 4, 7, 8, 11, 12, 15, 16, 19, 20, 100]
        #expect(distances.map(ConsensioRules.points(distance:)) == [5, 5, 4, 4, 3, 3, 2, 2, 1, 1, 0, 0])
    }

    @Test func verdictsFollowTheDistance() {
        #expect(ConsensioRules.verdict(distance: 3) == .spotOn)
        #expect(ConsensioRules.verdict(distance: 4) == .soClose)
        #expect(ConsensioRules.verdict(distance: 11) == .soClose)
        #expect(ConsensioRules.verdict(distance: 12) == .close)
        #expect(ConsensioRules.verdict(distance: 19) == .close)
        #expect(ConsensioRules.verdict(distance: 20) == .far)
    }

    @Test func ownTopicsFollowTheServersLimits() {
        #expect(ConsensioRules.ownTopicIssue(subject: "W", leftEnd: "No", rightEnd: "Yes") == .subject)
        #expect(ConsensioRules.ownTopicIssue(subject: "Waffles", leftEnd: " ", rightEnd: "Yes") == .end)
        #expect(ConsensioRules.ownTopicIssue(subject: "Waffles", leftEnd: "Yes", rightEnd: "YES") == .sameEnds)
        let waffles = ConsensioRules.ownTopicIssue(
            subject: "  Your mom's\nwaffles ",
            leftEnd: "Not again",
            rightEnd: "Every Sunday"
        )
        #expect(waffles == nil)
        #expect(ConsensioRules.normalized("  Your  mom's\nwaffles ") == "Your mom's waffles")
    }

    @Test func aStateIsOlderOnlyAtALowerVersionOfTheSameGame() throws {
        let user = UUID()
        let couple = UUID()
        let gameID = UUID()
        func state(version: Int?, epoch: String = "") -> RemoteConsensioState {
            RemoteConsensioState(
                userID: user,
                partnerUserID: nil,
                coupleID: couple,
                dataEpoch: epoch,
                game: version.map {
                    RemoteConsensioGame(
                        id: gameID, turnUserID: user, turnStartedAt: .now, choices: [], sharedPoints: 0,
                        roundCount: 0, version: $0, createdByUserID: user, createdAt: .now, updatedAt: .now
                    )
                },
                currentRound: nil,
                previousRound: nil
            )
        }
        #expect(state(version: 1).isOlder(than: state(version: 2)))
        #expect(!state(version: 2).isOlder(than: state(version: 1)))
        #expect(state(version: nil).isOlder(than: state(version: 1)))
        #expect(!state(version: 1, epoch: "a").isOlder(than: state(version: 2, epoch: "b")))
    }

    /// The relay carries only the guess pin. Nothing that crosses it may hold the real spot.
    @Test func theLiveMessageHasNoPlaceForTheRealSpot() throws {
        let message = ConsensioLiveMessage(roundID: UUID(), position: 40, touching: true)
        let data = try JSONEncoder().encode(GameLiveEnvelope(game: ConsensioLiveMessage.game, message: message))
        let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fields = try #require(envelope["message"] as? [String: Any])
        #expect(Set(fields.keys) == ["roundID", "position", "touching"])
    }

    // swiftlint:disable line_length
    @Test func theStateDecodesFromTheServersShape() throws {
        let json = """
        {"user_id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","partner_user_id":null,
         "couple_id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","data_epoch":"",
         "game":{"id":"8F9619FF-8B86-D011-B42D-00C04FC964FF","turn_user_id":"6F9619FF-8B86-D011-B42D-00C04FC964FF",
           "turn_started_at":"2026-10-18T12:00:00.000Z",
           "choices":[{"topic_id":"camping","language":"en","subject":"Camping","left_end":"Never again","right_end":"Book it now"}],
           "shared_points":4,"round_count":1,"version":3,"created_by_user_id":"6F9619FF-8B86-D011-B42D-00C04FC964FF",
           "created_at":"2026-10-18T12:00:00.000Z","updated_at":"2026-10-18T12:00:00.000Z"},
         "current_round":{"id":"9F9619FF-8B86-D011-B42D-00C04FC964FF","round_number":1,
           "placer_user_id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","guesser_user_id":"6F9619FF-8B86-D011-B42D-00C04FC964FF",
           "topic_id":null,"language":null,"subject":"Waffles","left_end":"No","right_end":"Yes","spot":null,
           "placed_at":"2026-10-18T12:00:00.000Z","guess":null,"distance":null,"points":null,"guessed_at":null,
           "my_reveal_seen_at":null},
         "previous_round":null}
        """
        let state = try PaeoniaConvexClient.decoder.decode(RemoteConsensioState.self, from: Data(json.utf8))
        #expect(state.game?.choices.first?.topicID == "camping")
        #expect(state.currentRound?.spot == nil)
        #expect(state.currentRound?.topicID == nil)
    }
    // swiftlint:enable line_length
}
