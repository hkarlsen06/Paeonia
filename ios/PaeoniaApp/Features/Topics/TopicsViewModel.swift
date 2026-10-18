import Foundation
import Observation

/// The topics: the card on the Questions tab, the shelf, and each topic's screen.
/// Reads the phone's copy first (`TopicsCaching`), follows the overview through
/// `TopicsLiveFeed` and the open topic through its own subscription. Answering a
/// topic question goes through `DailyChallengeViewModel`, which this hands the
/// topic's questions to, so drafts, sending, the reveal and the chat are shared.
@MainActor
@Observable
final class TopicsViewModel {
    enum Notice: Equatable {
        case loadFailed(PaeoniaFailure)
        case skipFailed(PaeoniaFailure)
        case adultCheckFailed(PaeoniaFailure)
    }

    private let gateway: (any TopicsGateway)?
    private let cache: any TopicsCaching
    private let locale: Locale
    @ObservationIgnored private weak var dailyChallenge: DailyChallengeViewModel?

    private(set) var currentUserID: UUID?
    private(set) var coupleID: UUID?
    private(set) var overview: [TopicSummary] = []
    /// The viewer hid the adults-only topic, so the shelf offers to show it again.
    private(set) var adultTopicsHiddenByViewer = false
    /// The overview has been read once, from the phone or the server.
    private(set) var hasLoadedOverview = false
    /// Each opened topic's questions, by topic key.
    private(set) var items: [String: [TopicQuestionItem]] = [:]
    /// Topics whose first read failed with nothing on the phone to show, and why.
    private(set) var failedTopics: [String: PaeoniaFailure] = [:]
    /// Skips sent but not yet in a server read, by question id. They show at once.
    private(set) var pendingSkips: [UUID: Bool] = [:]
    /// Questions this phone has shown in each topic. More questions later count as new.
    private(set) var seenQuestionIDs: [String: Set<UUID>] = [:]
    private(set) var celebratedTopicKeys: Set<String> = []
    /// The finished moment to show over a topic's screen, by topic key.
    var celebratingTopicKey: String?
    var notice: Notice?

    @ObservationIgnored private var observeTask: Task<Void, Never>?
    // ponytail: every opened topic stays followed until sign-out or the topic closes.
    // At six topics that is cheap. Stop idle ones if topics grow into the dozens.
    /// The live subscription of each topic opened since sign-in, by key. The view model
    /// owns them, not the topic screen, so the answer cover and a question's page keep
    /// getting the partner's answers while they cover the screen.
    @ObservationIgnored private var followTasks: [String: Task<Void, Never>] = [:]
    /// Skips the server accepted. The next read of their topic decides, whatever it says.
    @ObservationIgnored private var acknowledgedSkips: Set<UUID> = []
    @ObservationIgnored private var details: [String: RemoteTopicDetail] = [:]

    init(
        gateway: (any TopicsGateway)? = LiveTopicsGateway.live(),
        cache: any TopicsCaching = FileTopicsCache.shared,
        locale: Locale = .current
    ) {
        self.gateway = gateway
        self.cache = cache
        self.locale = locale
    }

    /// Ties answering to the daily challenge, which owns drafts and the send queue.
    func attach(dailyChallenge: DailyChallengeViewModel) {
        self.dailyChallenge = dailyChallenge
    }

    /// Loads the phone's copy for this person, then follows changes. A change of the
    /// signed-in user starts over. The couple id may arrive after launch and only
    /// rebuilds the questions.
    func configure(currentUserID: UUID?, coupleID: UUID?) async {
        let userChanged = self.currentUserID != currentUserID
        self.coupleID = coupleID
        guard userChanged else {
            rebuildAllItems()
            return
        }
        self.currentUserID = currentUserID
        overview = []
        adultTopicsHiddenByViewer = false
        hasLoadedOverview = false
        items = [:]
        failedTopics = [:]
        pendingSkips = [:]
        seenQuestionIDs = [:]
        celebratedTopicKeys = []
        celebratingTopicKey = nil
        observeTask?.cancel()
        followTasks.values.forEach { $0.cancel() }
        followTasks = [:]
        acknowledgedSkips = []
        details = [:]
        guard let currentUserID else { return }

        await readCache(for: currentUserID)
        observeTask = Task { @MainActor [weak self] in
            for await change in LocalStoreChanges.changes(in: .topics) {
                guard change.ownerUserID == currentUserID else { continue }
                guard let self, self.currentUserID == currentUserID else { return }
                await self.readCache(for: currentUserID)
            }
        }
        await refreshOverview()
    }

    /// One read of the overview, for pull to refresh and the first launch before the
    /// live feed has delivered.
    func refreshOverview() async {
        guard let gateway, let currentUserID else { return }
        do {
            let overview = try await gateway.loadOverview()
            guard self.currentUserID == currentUserID else { return }
            await cache.saveOverview(overview, ownerUserID: currentUserID)
            apply(overview)
        } catch {
            // The live feed keeps trying. The card keeps what the phone has.
        }
    }

}

extension TopicsViewModel {
    // MARK: - Overview

    func topic(_ key: String) -> TopicSummary? {
        overview.first { $0.id == key }
    }

    /// The Topics card's line about what's waiting, or nil when nothing is.
    func hook(partnerName: String, unreadTopicChats: [DailyQuestionThreadSummary]) -> TopicsHook? {
        TopicsHook.make(overview: overview, unreadTopicChats: unreadTopicChats, partnerName: partnerName)
    }

    /// The topics the Topics card shows small: the ones with the most going on.
    var cardTopics: [TopicSummary] {
        let shown = overview.filter(\.isOpen)
        let busy = shown.sorted {
            ($0.forYouCount, $0.togetherCount, -$0.sortOrder) > ($1.forYouCount, $1.togetherCount, -$1.sortOrder)
        }
        return Array(busy.prefix(3))
    }

    /// Questions added to a topic since this phone first showed it.
    func newQuestionCount(for key: String) -> Int {
        guard let seen = seenQuestionIDs[key], !seen.isEmpty, let topicItems = items[key] else { return 0 }
        return topicItems.filter { !seen.contains($0.id) && !$0.isSkipped }.count
    }

    // MARK: - One topic

    /// Starts following a topic, once. Its screen calls this when it appears.
    func open(_ key: String) {
        guard followTasks[key] == nil, currentUserID != nil else { return }
        followTasks[key] = Task { @MainActor [weak self] in
            await self?.follow(key)
            self?.followTasks[key] = nil
        }
    }

    /// Shows what the phone has, then follows the topic. Runs until the task is
    /// cancelled, the signed-in user changes, or the topic stops being open.
    func follow(_ key: String) async {
        guard let gateway, let currentUserID else { return }
        if items[key] == nil {
            do {
                let detail = try await gateway.loadTopic(key: key)
                guard self.currentUserID == currentUserID else { return }
                await store(detail, ownerUserID: currentUserID)
                failedTopics[key] = nil
            } catch {
                guard !error.isCancellation, self.currentUserID == currentUserID else { return }
                if items[key] == nil {
                    failedTopics[key] = PaeoniaFailure(error)
                } else {
                    notice = .loadFailed(PaeoniaFailure(error))
                }
            }
        }
        for await detail in gateway.topicUpdates(key: key) {
            guard !Task.isCancelled, self.currentUserID == currentUserID else { return }
            await store(detail, ownerUserID: currentUserID)
            failedTopics[key] = nil
        }
    }

    /// Tries a failed first read again.
    func retry(_ key: String) {
        failedTopics[key] = nil
        followTasks[key]?.cancel()
        followTasks[key] = nil
        open(key)
    }

    func sections(for key: String) -> TopicSections {
        let isSending = { [dailyChallenge] (id: UUID) in dailyChallenge?.isSending(id) ?? false }
        return TopicSections(items: displayedItems(for: key), isSending: isSending)
    }

    /// The topic's questions with skips this phone sent but the server hasn't confirmed.
    func displayedItems(for key: String) -> [TopicQuestionItem] {
        (items[key] ?? []).map { item in
            guard let pending = pendingSkips[item.id], pending != item.isSkipped else { return item }
            return TopicQuestionItem(question: item.question, sortOrder: item.sortOrder, isSkipped: pending)
        }
    }

    /// The topic screen showed these questions, so later ones count as new.
    func markShown(_ key: String) {
        guard let currentUserID, let topicItems = items[key], !topicItems.isEmpty else { return }
        let ids = Set(topicItems.map(\.id))
        guard !(seenQuestionIDs[key] ?? []).isSuperset(of: ids) else { return }
        seenQuestionIDs[key, default: []].formUnion(ids)
        let cache = cache
        Task { await cache.markSeen(ids, topicKey: key, ownerUserID: currentUserID) }
    }

    /// The next question to answer in the question's topic, after it.
    func nextQuestion(after question: DailyChallengeQuestion) -> DailyChallengeQuestion? {
        guard let key = question.topicKey else { return nil }
        return sections(for: key).next(after: question.id)?.question
    }

    // MARK: - Skipping

    /// Puts a question aside for both partners, or brings it back. Shows at once and
    /// goes back if the server refuses.
    func setSkipped(_ question: DailyChallengeQuestion, skipped: Bool) async {
        guard let gateway else { return }
        pendingSkips[question.id] = skipped
        do {
            try await gateway.setSkipped(questionID: question.questionID, skipped: skipped)
            // The live read may still carry the state from before, so the override
            // stays until a read made after the skip. The partner may already have
            // brought the question back by answering it, and that read decides.
            acknowledgedSkips.insert(question.id)
            if let key = question.topicKey, let currentUserID,
               let detail = try? await gateway.loadTopic(key: key), self.currentUserID == currentUserID {
                await store(detail, ownerUserID: currentUserID)
            }
        } catch {
            guard !error.isCancellation else { return }
            pendingSkips[question.id] = nil
            notice = .skipFailed(PaeoniaFailure(error))
        }
    }

    // MARK: - Adults-only topic

    /// Saves the age check's outcome. Nothing about the person's age is sent, only
    /// whether the topic may open.
    func saveAdultTopicsStatus(_ status: AdultTopicsStatus) async {
        guard let gateway else { return }
        do {
            try await gateway.setAdultTopicsStatus(status)
            await refreshOverview()
        } catch {
            guard !error.isCancellation else { return }
            notice = .adultCheckFailed(PaeoniaFailure(error))
        }
    }

    func reportAdultCheckFailure(_ failure: PaeoniaFailure) {
        notice = .adultCheckFailed(failure)
    }

    func dismissNotice() {
        notice = nil
    }

    // MARK: - Finished moment

    func finishCelebration() {
        guard let key = celebratingTopicKey, let currentUserID else {
            celebratingTopicKey = nil
            return
        }
        celebratingTopicKey = nil
        celebratedTopicKeys.insert(key)
        let cache = cache
        Task { await cache.markCelebrated(topicKey: key, ownerUserID: currentUserID) }
    }

    // MARK: - Chat from elsewhere

    /// A topic question's page, opened from a chat notification: the question with
    /// `questionID` in `topicKey`, read from the server when the phone doesn't have it.
    func chatQuestion(questionID: UUID, topicKey: String) async -> DailyChallengeQuestion? {
        if let question = items[topicKey]?.first(where: { $0.question.questionID == questionID })?.question,
           question.isChatAvailable {
            return question
        }
        guard let gateway, let currentUserID, let detail = try? await gateway.loadTopic(key: topicKey) else {
            return nil
        }
        await store(detail, ownerUserID: currentUserID)
        // The page then follows the partner's answers in this topic.
        open(topicKey)
        let question = items[topicKey]?.first { $0.question.questionID == questionID }?.question
        return question?.isChatAvailable == true ? question : nil
    }

    // MARK: - Reading

    private func readCache(for userID: UUID) async {
        let document = await cache.document(ownerUserID: userID)
        guard currentUserID == userID else { return }
        seenQuestionIDs = document.seenQuestionIDs
        celebratedTopicKeys = document.celebratedTopicKeys
        // Topics show only once the overview says which ones are open.
        guard let overview = document.overview else { return }
        apply(overview)
        for detail in document.details.values {
            applyDetail(detail)
        }
    }

    private func apply(_ remote: RemoteTopicsOverview) {
        overview = remote.topics.map { TopicSummary($0, locale: locale) }.sorted { $0.sortOrder < $1.sortOrder }
        adultTopicsHiddenByViewer = remote.adultTopicsHiddenByViewer
        hasLoadedOverview = true
        // A topic the couple can no longer open, such as the adults-only one after a
        // partner hid it, leaves the phone: its questions, answers and saved copy.
        let closed = Set(details.keys).union(items.keys).union(followTasks.keys).subtracting(openTopicKeys)
        for key in closed {
            close(key)
        }
    }

    private var openTopicKeys: Set<String> {
        Set(overview.filter(\.isOpen).map(\.id))
    }

    private func close(_ key: String) {
        followTasks[key]?.cancel()
        followTasks[key] = nil
        details[key] = nil
        items[key] = nil
        failedTopics[key] = nil
        dailyChallenge?.setTopicQuestions([], topicKey: key)
        if let currentUserID {
            let cache = cache
            Task { await cache.removeDetail(topicKey: key, ownerUserID: currentUserID) }
        }
    }

    private func store(_ detail: RemoteTopicDetail, ownerUserID: UUID) async {
        guard openTopicKeys.contains(detail.topic.topicKey) else { return }
        await cache.saveDetail(detail, ownerUserID: ownerUserID)
        guard currentUserID == ownerUserID else { return }
        applyDetail(detail)
    }

    /// Builds a topic's questions only while the overview says it is open.
    private func applyDetail(_ detail: RemoteTopicDetail) {
        let key = detail.topic.topicKey
        guard openTopicKeys.contains(key) else {
            close(key)
            return
        }
        details[key] = detail
        buildItems(for: detail)
    }

    private func rebuildAllItems() {
        for detail in details.values {
            buildItems(for: detail)
        }
    }

    private func buildItems(for detail: RemoteTopicDetail) {
        guard let currentUserID, let coupleID else { return }
        let key = detail.topic.topicKey
        let built = TopicQuestionItem.items(
            from: detail,
            currentUserID: currentUserID,
            coupleID: coupleID,
            locale: locale
        )
        // A skip the server now reports, or one it accepted earlier, needs no local
        // override any more. This read is newer than the skip.
        for item in built where pendingSkips[item.id] == item.isSkipped || acknowledgedSkips.contains(item.id) {
            pendingSkips[item.id] = nil
            acknowledgedSkips.remove(item.id)
        }
        let wasFinished = items[key].map { Self.isFinished($0) } ?? true
        items[key] = built
        dailyChallenge?.setTopicQuestions(built.map(\.question), topicKey: key)
        if !wasFinished, Self.isFinished(built), !celebratedTopicKeys.contains(key) {
            celebratingTopicKey = key
        }
    }

    /// Every question the couple kept has both answers.
    private static func isFinished(_ items: [TopicQuestionItem]) -> Bool {
        let kept = items.filter { !$0.isSkipped }
        return !kept.isEmpty && kept.allSatisfy { $0.question.hasOwnAnswer && $0.question.hasPartnerAnswer }
    }
}
