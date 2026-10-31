import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct StoryChainLiveReactionTests {
    @Test func aDraftFromTheCommandLinePartnerReachesThePage() async {
        let environment = StoryChainTestEnvironment.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.start()
        defer { viewModel.stop() }
        environment.connection.partnerJoins(role: "drawing")

        let json = """
        {"game":"story_chain","message":{"draft":{"_0":{
          "story":"\(StoryChainFixture.storyID)","number":2,"text":"The key turned.","last":false,"sent":false
        }}}}
        """
        environment.connection.onGameData?(Data(json.utf8))

        #expect(viewModel.page.ghost?.text == "The key turned.")
    }

    @Test func reactionsTravelBothWaysWithoutReplacingTheDraft() async throws {
        let writer = StoryChainTestEnvironment.myTurnAfterPartner()
        let reader = StoryChainTestEnvironment.waitingOnPartner()
        let writing = writer.viewModel()
        let reading = reader.viewModel()
        await writing.start()
        await reading.start()
        defer {
            writing.stop()
            reading.stop()
        }
        writer.connection.partnerJoins(role: "watching")
        reader.connection.partnerJoins(role: "drawing")

        writing.draft = "The door opened."
        #expect(await waitUntil { writer.connection.sentMessages.last?.text == "The door opened." })
        reader.connection.onGameData?(try #require(writer.connection.sentGameData.last))
        #expect(reading.page.ghost?.text == "The door opened.")

        writing.sendLiveReaction(.exclamation)
        reader.connection.onGameData?(try #require(writer.connection.sentGameData.last))
        #expect(writing.liveReactions.flights.map(\.reaction) == [.exclamation])
        #expect(reading.liveReactions.flights.map(\.reaction) == [.exclamation])
        #expect(reading.page.ghost?.text == "The door opened.")

        reading.sendLiveReaction(.love)
        writer.connection.onGameData?(try #require(reader.connection.sentGameData.last))
        #expect(writing.liveReactions.flights.map(\.reaction) == [.exclamation, .love])
        #expect(writing.draft == "The door opened.")
    }

    @Test func otherStoriesAndAnAbsentPartnerCannotProduceReactions() async throws {
        let environment = StoryChainTestEnvironment.waitingOnPartner()
        let viewModel = environment.viewModel()
        await viewModel.start()
        defer { viewModel.stop() }
        environment.connection.partnerJoins(role: "drawing")

        let message = StoryChainRoomMessage.reaction(story: UUID(), reaction: .question)
        environment.connection.onGameData?(try JSONEncoder().encode(GameLiveEnvelope(
            game: StoryChainRoomMessage.game,
            message: message
        )))
        #expect(viewModel.liveReactions.flights.isEmpty)

        environment.connection.onMessage?(WidgetLiveMessage(type: .left, id: "partner"))
        let sentCount = environment.connection.sentGameData.count
        viewModel.sendLiveReaction(.laugh)
        #expect(!viewModel.canSendLiveReaction)
        #expect(environment.connection.sentGameData.count == sentCount)
        #expect(viewModel.liveReactions.flights.isEmpty)
    }
}
