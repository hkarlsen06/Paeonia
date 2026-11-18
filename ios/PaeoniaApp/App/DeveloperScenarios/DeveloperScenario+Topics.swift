#if DEBUG
  import SwiftUI

  nonisolated extension DeveloperScenario {
    static let topics: [DeveloperScenario] = [topicFinished, topicPrivateConsent]

    /// The question asked before Flirt opens for the first time, over the Topics shelf.
    static let topicPrivateConsent = DeveloperScenario(
      "topic-private-consent", "Topics · private topic question",
      "The Topics shelf with the question a person answers before Flirt opens for the first time", .questions
    ) { _ in DeveloperPrivateTopicConsentScenarioView() }

    /// The moment a couple finishes a topic. It opens `TopicFinishedView` on its own over the
    /// topic screen's background, so the celebration plays as the scenario opens.
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

  /// The production shelf and question, with an in-memory topics backend. A yes is
  /// saved there and closes the question, and tapping Flirt asks again after "Not now".
  private struct DeveloperPrivateTopicConsentScenarioView: View {
    @State private var topics = DeveloperTopicsFixture.viewModel(consented: false)
    @State private var asking: TopicSummary?

    var body: some View {
      NavigationStack {
        TopicsShelfView(viewModel: topics) { key in
          if topics.needsPrivateTopicsConsent(toOpen: key) {
            asking = topics.topic(key)
          }
        }
      }
      .task {
        await topics.configure(
          currentUserID: DeveloperScenarioFixture.currentUserID, coupleID: DeveloperScenarioFixture.coupleID
        )
        asking = topics.privateTopics.first
      }
      .sheet(item: $asking) { topic in
        PrivateTopicConsentSheet(
          topicKey: topic.id, topicName: topic.title, viewModel: topics, onConsented: { asking = nil }
        )
      }
    }
  }

  /// A shelf of two topics, one of them the private topic Flirt, kept in memory.
  enum DeveloperTopicsFixture {
    static func viewModel(consented: Bool) -> TopicsViewModel {
      TopicsViewModel(
        gateway: DeveloperTopicsGateway(consented: consented), cache: DeveloperTopicsCache(),
        locale: Locale(identifier: "en")
      )
    }

    nonisolated static func overview(consented: Bool) -> RemoteTopicsOverview {
      RemoteTopicsOverview(
        topics: [
          RemoteTopicSummary(
            topicKey: "travel_and_places", collectionID: DeveloperScenarioFixture.coupleID, sortOrder: 1,
            isPrivate: false, titleEN: "Travel and places", subtitleEN: "Places together",
            titleNB: "Reiser og steder", subtitleNB: "Steder sammen",
            totalCount: 21, togetherCount: 4, forYouCount: 0, waitingForPartnerCount: 1
          ),
          RemoteTopicSummary(
            topicKey: "flirt", collectionID: DeveloperScenarioFixture.partnerUserID, sortOrder: 2,
            isPrivate: true, titleEN: "Flirt", subtitleEN: "A little spark",
            titleNB: "Flørt", subtitleNB: "En liten gnist",
            totalCount: 31, togetherCount: 0, forYouCount: 0, waitingForPartnerCount: 0
          ),
        ],
        privateTopicsConsented: consented
      )
    }
  }

  private actor DeveloperTopicsGateway: TopicsGateway {
    private var consented: Bool

    init(consented: Bool) {
      self.consented = consented
    }

    func loadOverview() -> RemoteTopicsOverview {
      DeveloperTopicsFixture.overview(consented: consented)
    }

    func loadTopic(key _: String) throws -> RemoteTopicDetail {
      throw URLError(.resourceUnavailable)
    }

    func setSkipped(questionID _: UUID, skipped _: Bool) {}

    func setPrivateTopicsConsent(_ consents: Bool, notice _: String) {
      consented = consents
    }

    nonisolated func topicUpdates(key _: String) -> AsyncStream<RemoteTopicDetail> {
      AsyncStream { $0.finish() }
    }
  }

  private actor DeveloperTopicsCache: TopicsCaching {
    private var stored = TopicsCacheDocument()

    func document(ownerUserID _: UUID) -> TopicsCacheDocument { stored }
    func saveOverview(_ overview: RemoteTopicsOverview, ownerUserID _: UUID) { stored.overview = overview }
    func saveDetail(_ detail: RemoteTopicDetail, ownerUserID _: UUID) { stored.details[detail.topic.topicKey] = detail }
    func removeDetail(topicKey: String, ownerUserID _: UUID) { stored.details[topicKey] = nil }
    func markSeen(_ questionIDs: Set<UUID>, topicKey: String, ownerUserID _: UUID) {
      stored.seenQuestionIDs[topicKey, default: []].formUnion(questionIDs)
    }
    func markCelebrated(topicKey: String, ownerUserID _: UUID) { stored.celebratedTopicKeys.insert(topicKey) }
    func clearAll() { stored = TopicsCacheDocument() }
  }
#endif
