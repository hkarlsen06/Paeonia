import Foundation
import Testing
@testable import PaeoniaApp

private enum TopicIDs {
    static let me = TestDailyChallengeIDs.currentUser
    static let partner = TestDailyChallengeIDs.partnerUser
    static let couple = TestDailyChallengeIDs.couple
    static let collection = dailyFixedUUID("66666666-6666-6666-6666-666666666666")
    static let startedQuestion = dailyFixedUUID("77777777-7777-7777-7777-777777777777")
    static let freshQuestion = dailyFixedUUID("88888888-8888-8888-8888-888888888888")
    static let partnerAnswer = dailyFixedUUID("99999999-9999-9999-9999-999999999999")
    static let version = dailyFixedUUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
}

private func summaryJSON(
    key: String = "travel_and_places",
    isPrivate: Bool = false,
    total: Int = 2,
    together: Int = 0,
    forYou: Int = 1
) -> String {
    """
    {"topic_key":"\(key)","collection_id":"\(TopicIDs.collection)","sort_order":4,
     "private":\(isPrivate),"title_en":"Travel and places","subtitle_en":"Where you've been.",
     "title_nb":"Reiser og steder","subtitle_nb":"Hvor du har vært.",
     "total_count":\(total),"together_count":\(together),"for_you_count":\(forYou),
     "waiting_for_partner_count":0}
    """
}

/// One question the partner started and answered, and one nobody has started.
private func detailJSON() -> String {
    let instance = TopicInstanceID.make(coupleID: TopicIDs.couple, questionID: TopicIDs.startedQuestion)
    let started = """
    {"question_id":"\(TopicIDs.startedQuestion)","question_key":"travel_best_view",
     "question_version_id":"\(TopicIDs.version)","sort_order":1,
     "prompt_en":"Best view?","short_prompt_en":"The best view",
     "prompt_nb":"Fineste utsikt?","short_prompt_nb":"Den fineste utsikten",
     "answer_kinds":["photo","text"],"is_skipped":false,
     "row":{"couple_day_id":"\(TestDailyChallengeIDs.coupleDay)","couple_id":"\(TopicIDs.couple)",
            "local_date":"2026-10-18","starts_at":"2026-10-18T00:00:00.000Z",
            "ends_at":"2026-10-19T00:00:00.000Z","instance_id":"\(instance)",
            "seeded_for_user_id":"\(TopicIDs.partner)","slot_number":0,"instance_status":"active",
            "question_id":"\(TopicIDs.startedQuestion)","question_version_id":"\(TopicIDs.version)",
            "question_key":"travel_best_view","prompt_en":"Best view?","short_prompt_en":"The best view",
            "prompt_nb":"Fineste utsikt?","short_prompt_nb":"Den fineste utsikten",
            "answer_kinds":["photo","text"],"own_answer_id":null,"own_answered_at":null,
            "partner_answer_id":"\(TopicIDs.partnerAnswer)",
            "partner_answered_at":"2026-10-18T10:00:00.000Z","can_view_partner_answer":false,
            "is_current_day":false,"topic_key":"travel_and_places","chat_available":false}}
    """
    let fresh = """
    {"question_id":"\(TopicIDs.freshQuestion)","question_key":"travel_best_souvenir",
     "question_version_id":"\(TopicIDs.version)","sort_order":2,
     "prompt_en":"Best souvenir?","short_prompt_en":"The best souvenir",
     "prompt_nb":"Beste suvenir?","short_prompt_nb":"Den beste suveniren",
     "answer_kinds":["text"],"is_skipped":false,"row":null}
    """
    return #"{"topic":\#(summaryJSON()),"questions":[\#(started),\#(fresh)],"answer_details":[]}"#
}

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try PaeoniaConvexClient.decoder.decode(type, from: Data(json.utf8))
}

private func items(locale: Locale = Locale(identifier: "en")) throws -> [TopicQuestionItem] {
    TopicQuestionItem.items(
        from: try decode(RemoteTopicDetail.self, detailJSON()),
        currentUserID: TopicIDs.me,
        coupleID: TopicIDs.couple,
        locale: locale
    )
}

struct TopicModelTests {
    @Test func instanceIDIsTheSameOnBothPhonesAndAValidUUID() {
        let first = TopicInstanceID.make(coupleID: TopicIDs.couple, questionID: TopicIDs.freshQuestion)
        let second = TopicInstanceID.make(coupleID: TopicIDs.couple, questionID: TopicIDs.freshQuestion)
        let other = TopicInstanceID.make(coupleID: TopicIDs.couple, questionID: TopicIDs.startedQuestion)
        #expect(first == second)
        #expect(first != other)
        let text = first.uuidString.lowercased()
        #expect(Array(text)[14] == "5")
        #expect("89ab".contains(Array(text)[19]))
    }

    @Test func itemsUseTheStartedRowOrAnUnstartedQuestionUnderTheSharedID() throws {
        let built = try items()
        #expect(built.count == 2)
        let started = try #require(built.first { $0.question.questionID == TopicIDs.startedQuestion })
        #expect(started.question.origin == .partner)
        #expect(started.question.hasPartnerAnswer)
        #expect(started.question.topicKey == "travel_and_places")
        let fresh = try #require(built.first { $0.question.questionID == TopicIDs.freshQuestion })
        #expect(fresh.id == TopicInstanceID.make(coupleID: TopicIDs.couple, questionID: TopicIDs.freshQuestion))
        #expect(fresh.question.origin == .own)
        #expect(fresh.question.isTopicQuestion)
        #expect(fresh.question.isAvailableToAnswer)
        #expect(fresh.question.shortPrompt == "The best souvenir")
    }

    @Test func stateFollowsWhoAnswered() throws {
        let built = try items()
        let started = try #require(built.first { $0.question.questionID == TopicIDs.startedQuestion })
        let fresh = try #require(built.first { $0.question.questionID == TopicIDs.freshQuestion })
        #expect(started.state(isSending: false) == .forYou)
        #expect(started.state(isSending: true) == .together)
        #expect(fresh.state(isSending: false) == .upNext)
        #expect(fresh.state(isSending: true) == .waitingForPartner)
        let skipped = TopicQuestionItem(question: fresh.question, sortOrder: 2, isSkipped: true)
        #expect(skipped.state(isSending: false) == .skipped)
    }
}

struct TopicsHookTests {
    private func summary(_ key: String, isPrivate: Bool = false, forYou: Int) throws -> TopicSummary {
        let json = summaryJSON(key: key, isPrivate: isPrivate, forYou: forYou)
        return TopicSummary(try decode(RemoteTopicSummary.self, json))
    }

    private func chat(topicKey: String?, isPrivate: Bool) -> DailyQuestionThreadSummary {
        DailyQuestionThreadSummary(
            threadID: UUID(), coupleID: TopicIDs.couple, questionID: UUID(), createdAt: Date(), updatedAt: Date(),
            lastMessageID: UUID(), lastMessageAt: Date(), lastMessageSenderUserID: TopicIDs.partner,
            lastMessageBody: "hi", topicKey: topicKey, isPrivateTopic: isPrivate
        )
    }

    @Test func namesTheOneTopicWithAnswers() throws {
        let overview = [try summary("travel_and_places", forYou: 2)]
        let hook = TopicsHook.make(overview: overview, unreadTopicChats: [], partnerName: "Robin")
        #expect(hook == .answeredIn(partner: "Robin", count: 2, topic: overview[0].title))
    }

    @Test func neverNamesAPrivateTopic() throws {
        let overview = [try summary("flirt", isPrivate: true, forYou: 1)]
        let hook = TopicsHook.make(overview: overview, unreadTopicChats: [], partnerName: "Robin")
        #expect(hook == .answeredForYou(partner: "Robin", count: 1))
        let chatHook = TopicsHook.make(
            overview: [try summary("flirt", isPrivate: true, forYou: 0)],
            unreadTopicChats: [chat(topicKey: "flirt", isPrivate: true)],
            partnerName: "Robin"
        )
        #expect(chatHook == .messageFrom(partner: "Robin"))
    }
}

struct TopicAnswerQueueTests {
    @Test func aQueuedAnswerWithoutATopicStillDecodes() throws {
        let json = #"{"instanceID":"\#(UUID())","answerID":"\#(UUID())","content":{"text":{"_0":"hei"}}}"#
        let payload = try JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: Data(json.utf8))
        #expect(payload.topicQuestionID == nil)
    }

    @MainActor
    @Test func aTopicAnswerGoesToTheTopicMutation() async throws {
        let gateway = RecordingDailyChallengeGateway()
        let handler = DailySubmitAnswerPendingOperationHandler(
            mediaUploadService: RecordingMediaUploadService(assetID: UUID()),
            gateway: gateway,
            mediaDraftStore: InMemoryDailyAnswerMediaDraftStore()
        )
        let instanceID = TopicInstanceID.make(coupleID: TopicIDs.couple, questionID: TopicIDs.freshQuestion)
        let payload = DailySubmitAnswerOperationPayload(
            instanceID: instanceID,
            answerID: UUID(),
            content: .text("The view from the ferry"),
            topicQuestionID: TopicIDs.freshQuestion
        )
        let result = try await handler.send(
            dailyPendingSnapshot(requestData: try JSONEncoder().encode(payload)),
            context: dailyChallengeSyncContext()
        )
        #expect(result == .succeeded)
        let sent = await gateway.submittedTopicAnswers
        #expect(sent.count == 1)
        #expect(sent.first?.questionID == TopicIDs.freshQuestion)
        #expect(sent.first?.instanceID == instanceID)
    }
}

// MARK: - View model

private actor StubTopicsGateway: TopicsGateway {
    var overview: RemoteTopicsOverview
    var detail: RemoteTopicDetail
    var skipError: (any Error)?
    private(set) var skipCalls: [(UUID, Bool)] = []

    init(overview: RemoteTopicsOverview, detail: RemoteTopicDetail) {
        self.overview = overview
        self.detail = detail
    }

    func failSkips(with error: any Error) { skipError = error }
    func setOverview(_ value: RemoteTopicsOverview) { overview = value }
    func setDetail(_ value: RemoteTopicDetail) { detail = value }

    func loadOverview() -> RemoteTopicsOverview { overview }
    func loadTopic(key _: String) -> RemoteTopicDetail { detail }
    func setSkipped(questionID: UUID, skipped: Bool) throws {
        skipCalls.append((questionID, skipped))
        if let skipError { throw skipError }
    }
    nonisolated func topicUpdates(key _: String) -> AsyncStream<RemoteTopicDetail> { AsyncStream { $0.finish() } }
}

private actor InMemoryTopicsCache: TopicsCaching {
    private var documents: [UUID: TopicsCacheDocument] = [:]
    func document(ownerUserID: UUID) -> TopicsCacheDocument { documents[ownerUserID] ?? TopicsCacheDocument() }
    func saveOverview(_ overview: RemoteTopicsOverview, ownerUserID: UUID) {
        documents[ownerUserID, default: .init()].overview = overview
    }
    func saveDetail(_ detail: RemoteTopicDetail, ownerUserID: UUID) {
        documents[ownerUserID, default: .init()].details[detail.topic.topicKey] = detail
    }
    func removeDetail(topicKey: String, ownerUserID: UUID) {
        documents[ownerUserID, default: .init()].details[topicKey] = nil
    }
    func markSeen(_ questionIDs: Set<UUID>, topicKey: String, ownerUserID: UUID) {
        documents[ownerUserID, default: .init()].seenQuestionIDs[topicKey, default: []].formUnion(questionIDs)
    }
    func markCelebrated(topicKey: String, ownerUserID: UUID) {
        documents[ownerUserID, default: .init()].celebratedTopicKeys.insert(topicKey)
    }
    func clearAll() { documents = [:] }
}

@MainActor
struct TopicsViewModelTests {
    private func makeViewModel() async throws -> (TopicsViewModel, StubTopicsGateway) {
        let overview = try decode(RemoteTopicsOverview.self, #"{"topics":[\#(summaryJSON())]}"#)
        let gateway = StubTopicsGateway(overview: overview, detail: try decode(RemoteTopicDetail.self, detailJSON()))
        let viewModel = TopicsViewModel(
            gateway: gateway,
            cache: InMemoryTopicsCache(),
            locale: Locale(identifier: "en")
        )
        await viewModel.configure(currentUserID: TopicIDs.me, coupleID: TopicIDs.couple)
        return (viewModel, gateway)
    }

    @Test func aSkipShowsAtOnceAndGoesBackWhenRefused() async throws {
        let (viewModel, gateway) = try await makeViewModel()
        await viewModel.follow("travel_and_places")
        let topicItems = try #require(viewModel.items["travel_and_places"])
        let fresh = try #require(topicItems.first { $0.question.questionID == TopicIDs.freshQuestion })

        await gateway.failSkips(with: URLError(.notConnectedToInternet))
        await viewModel.setSkipped(fresh.question, skipped: true)
        #expect(viewModel.sections(for: "travel_and_places").skipped.isEmpty)
        #expect(viewModel.notice == .skipFailed(.offline))
        #expect(await gateway.skipCalls.first?.0 == TopicIDs.freshQuestion)
    }

    @Test func aTopicThatLeavesTheShelfLeavesThePhone() async throws {
        let (viewModel, gateway) = try await makeViewModel()
        await viewModel.follow("travel_and_places")
        #expect(viewModel.items["travel_and_places"] != nil)

        let empty = #"{"topics":[]}"#
        await gateway.setOverview(try decode(RemoteTopicsOverview.self, empty))
        await viewModel.refreshOverview()
        #expect(viewModel.items["travel_and_places"] == nil)
        // A late read of the removed topic doesn't bring it back.
        await viewModel.follow("travel_and_places")
        #expect(viewModel.items["travel_and_places"] == nil)
    }

    @Test func anAcceptedSkipYieldsToTheServersLaterAnswer() async throws {
        let (viewModel, _) = try await makeViewModel()
        await viewModel.follow("travel_and_places")
        let topicItems = try #require(viewModel.items["travel_and_places"])
        let fresh = try #require(topicItems.first { $0.question.questionID == TopicIDs.freshQuestion })

        // The stub keeps reporting the question as not skipped, as when the partner
        // answered it right after the skip.
        await viewModel.setSkipped(fresh.question, skipped: true)
        #expect(viewModel.pendingSkips.isEmpty)
        #expect(viewModel.sections(for: "travel_and_places").skipped.isEmpty)
    }
}
