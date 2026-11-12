#if DEBUG
  import SwiftUI

  /// The moment a couple finishes a topic. It opens `TopicFinishedView` on its own over the
  /// topic screen's background, so the celebration plays as the scenario opens.
  nonisolated extension DeveloperScenario {
    static let topics: [DeveloperScenario] = [topicFinished]

    static let topicFinished = DeveloperScenario(
      "topic-finished", "Topics · finished topic",
      "Every question in Travel and places answered together: the finished moment over the topic", .questions
    ) { _ in DeveloperTopicFinishedScenarioView() }
  }

  private struct DeveloperTopicFinishedScenarioView: View {
    private let topic = TopicSummary(RemoteTopicSummary(
      topicKey: "travel_and_places", collectionID: DeveloperScenarioFixture.coupleID, sortOrder: 1,
      isPrivate: false, titleEN: "Travel and places", subtitleEN: "Places together",
      titleNB: "Reiser og steder", subtitleNB: "Steder sammen",
      totalCount: 21, togetherCount: 21, forYouCount: 0, waitingForPartnerCount: 0
    ))

    var body: some View {
      ZStack {
        Color.paeoniaBackgroundPrimary
          .ignoresSafeArea()
        TopicFinishedView(topic: topic, onDone: {})
      }
    }
  }
#endif
