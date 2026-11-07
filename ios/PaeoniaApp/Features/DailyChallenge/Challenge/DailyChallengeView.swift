import SwiftUI

/// Today's unanswered challenge stays first. Outstanding conversations follow it,
/// then game presence and handled content. Earlier answer rounds remain in history.
struct DailyChallengeScreen: View {
    let viewModel: DailyChallengeViewModel
    /// Namespace for the daily question zoom transition. The hero card and each
    /// answerable row mark themselves as zoom sources in it, so the tapped card appears
    /// to grow into its full-screen answer flow.
    var zoomNamespace: Namespace.ID?
    var focusedQuestionIDs: Binding<[UUID]> = .constant([])
    var chatQuestion: Binding<DailyChallengeQuestion?> = .constant(nil)
    var requestedConversationID: Binding<UUID?> = .constant(nil)
    /// Set by the couple chat's push and deep link. The screen opens the chat and clears it.
    var isCoupleChatRequested: Binding<Bool> = .constant(false)
    var onOpenAnswerFlow: () -> Void = {}
    var onTapStreak: () -> Void = {}
    var onRefresh: (() async -> Void)?
    /// Opens the answer flow for a question opened from its row.
    var onAnswerPartnerQuestion: (DailyChallengeQuestion) -> Void = { _ in }
    var privacySafetyService: (any PrivacySafetyServicing)?
    var privacyOperationProvider: (any SyncClientOperationProviding)?
    var onReportedAndLeft: () -> Void = {}
    /// The memories and stories someone wrote about, each listed as a row for its chat.
    var conversations: [SubjectConversation] = []
    var storyPeople = StoryPeople(currentName: "", partnerName: "")
    /// Shows a story from its chat's header card. Nil leaves the card without a tap.
    var stories: StoriesViewModel?
    /// The Topics card under the daily question, which opens the extra questions.
    var topicsCard: TopicsCardContent?
    var coupleID: UUID?
    var partnerGameKinds: Set<GameKind> = []

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.threadChatContext) var chatContext

    /// The earlier days under today's list. Built once the signed-in user is known, and
    /// kept while a chat is open on top of this screen.
    @State var historyViewModel: DailyChallengeHistoryViewModel?
    @State private var highlightedQuestionIDs: Set<UUID> = []
    @State private var reportTarget: PrivacyReportTarget?
    /// Hides the tab bar while a chat is about to open, before the push starts. Hiding
    /// it from the pushed chat instead would bring it back only after the back swipe
    /// ends. Same approach as Tidex's chat.
    @State var isOpeningChat = false
    /// The memory's, story's or the couple's chat pushed on top of this screen.
    @State var conversationChat: ConversationChatDestination?
    /// The story opened from its chat's header card, over the chat.
    @State private var storyViewer: StoryViewerContent?

    private var isChatOpen: Bool {
        chatQuestion.wrappedValue != nil || conversationChat != nil
    }

    private var hidesTabBar: Bool {
        isChatOpen || isOpeningChat
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                    coupleChatCard
                    heroCard
                    if isDayComplete { topicsEntry }
                    rowsList(attentionRows)
                    if !isDayComplete { topicsEntry }
                    activeGameChats
                    rowsList(tabContent.recent)
                    topicsShelf
                    earlierDays
                }
                // The hero shrinking to one row moves everything under it with a glide.
                .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: isDayComplete)
                .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: isCalm)
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
                // The same gap above the tab bar as between the sections.
                .padding(.bottom, PaeoniaSpacing.sectionSpacing)
                .paeoniaReadableWidth(alignment: .leading)
            }
            .refreshable { await refresh() }
            .task(id: focusedQuestionIDs.wrappedValue) {
                await focusQuestionIfNeeded(proxy)
            }
            .task(id: viewModel.participants.currentUserID) {
                await loadEarlierDays()
            }
            // A new day turns yesterday's questions into earlier days.
            .onChange(of: viewModel.snapshot.coupleDayID) {
                Task { await reloadEarlierDays() }
            }
            .onChange(of: historyViewModel?.notice) { _, notice in
                showHistoryBanner(for: notice)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .keepsTabBarBottomInset(whileHidden: hidesTabBar)
        .paeoniaTabBackdrop()
        .clearsDeliveredQuestionTimeReminders()
        .navigationTitle(Text(.mainTabQuestions))
        .toolbarVisibility(hidesTabBar ? .hidden : .visible, for: .tabBar)
        .onChange(of: isChatOpen) { _, isOpen in
            if !isOpen { isOpeningChat = false }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The streak is sized to match the brand mark and carried in the toolbar's
            // standard background.
            if streakPill.isVisible {
                ToolbarItem(placement: .topBarTrailing) {
                    DailyStreakToolbarLabel(state: streakPill, onTap: onTapStreak)
                }
            }
        }
        .navigationDestination(item: $reportTarget) { reportTarget in
            if let partnerUserID = viewModel.participants.partnerUserID {
                ReportAndLeaveView(
                    partnerUserID: partnerUserID,
                    partnerName: viewModel.participants.partnerName,
                    reportTarget: reportTarget,
                    service: privacySafetyService,
                    operationProvider: privacyOperationProvider,
                    onReportedAndLeft: onReportedAndLeft
                )
            }
        }
        .navigationDestination(item: chatQuestion) { question in
            ThreadChatView(
                viewModel: viewModel.makeChatViewModel(question: question),
                question: viewModel.latestQuestion(question),
                participants: viewModel.participants,
                onReport: { reportTarget = $0 },
                sendingAnswer: viewModel.sendingPreview(for: viewModel.latestQuestion(question))
            )
            .analyticsScreen("daily_chat")
            .id(question.id)
        }
        .requestedConversation(
            id: requestedConversationID, conversations: conversations, isOpening: isOpeningChat, open: openConversation
        )
        .onChange(of: isCoupleChatRequested.wrappedValue, initial: true) { _, isRequested in
            guard isRequested else { return }
            isCoupleChatRequested.wrappedValue = false
            openCoupleChat()
        }
        .navigationDestination(item: $conversationChat) { destination in
            ThreadChatScreen(viewModel: destination.viewModel, onOpenHeader: openStoryAction(destination.story))
                .analyticsScreen(Self.analyticsScreenName(of: destination.viewModel.subject.kind))
                .id(destination.id)
                .fullScreenCover(item: $storyViewer) { content in
                    if let stories {
                        StoryViewer(content: content, people: storyPeople, viewModel: stories)
                            .analyticsScreen("story_viewer")
                    }
                }
        }
        .onChange(of: viewModel.notice) { _, notice in
            showBanner(for: notice)
        }
    }

    /// The couple's streak for the toolbar badge — derived from the live server streak.
    private var streakPill: StreakPillState {
        StreakPillState(viewModel.streak)
    }

    /// Whether the user has answered today's question. The big card then gives way to
    /// the conversation card for that question.
    private var isDayComplete: Bool {
        viewModel.homeCardState.kind == .complete
    }

    @ViewBuilder
    private var heroCard: some View {
        let state = viewModel.homeCardState
        if !isDayComplete {
            DailyPromptCard(
                state: DailyChallengeCardState(
                    kind: state.kind, hasPartnerAnsweredToday: state.hasPartnerAnsweredToday
                ),
                partnerName: viewModel.participants.partnerName,
                partnerPhotoAssetID: viewModel.participants.partnerProfilePhotoAssetID,
                onAnswer: onOpenAnswerFlow
            )
            .zoomSource(DailyFlowZoom.questions, in: zoomNamespace)
        }
    }

    /// Pull to refresh reloads today's questions and the earlier days together.
    private func refresh() async {
        async let earlier: Void = reloadEarlierDays()
        if let onRefresh {
            await onRefresh()
        } else {
            await viewModel.reload()
        }
        await earlier
    }

    private func reloadEarlierDays() async {
        await historyViewModel?.load()
    }

    /// Builds the earlier-days view model for the signed-in user (once, and again if the
    /// user changes) and loads it when nothing has loaded yet. Leaving for a chat cancels
    /// this task, and coming back finishes the load.
    private func loadEarlierDays() async {
        guard let userID = viewModel.participants.currentUserID else { return }
        let history: DailyChallengeHistoryViewModel
        if let existing = historyViewModel, existing.currentUserID == userID {
            history = existing
        } else {
            history = viewModel.makeHistoryViewModel()
            historyViewModel = history
        }
        guard history.needsLoad else { return }
        await history.load()
    }

    /// Reads the chat from the phone and hides the tab bar, then pushes the chat, so
    /// it opens complete with nothing moving in after.
    func openChat(_ question: DailyChallengeQuestion, newest: Bool = false) {
        guard !isOpeningChat else { return }
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) { isOpeningChat = true }
        Task {
            await viewModel.prepareChat(for: question, focusesNewest: newest)
            await Task.yield()
            chatQuestion.wrappedValue = question
        }
    }

    private func showHistoryBanner(for notice: DailyChallengeHistoryViewModel.Notice?) {
        guard let notice else { return }
        bannerCenter.show(
            .error(
                title: String(localized: notice.title),
                message: String(localized: notice.message)
            )
        )
        historyViewModel?.dismissNotice()
    }

    private func showBanner(for notice: DailyChallengeViewModel.Notice?) {
        guard let notice else { return }
        bannerCenter.show(
            .error(
                title: String(localized: notice.title),
                message: String(localized: notice.message(partnerName: viewModel.participants.partnerName))
            )
        )
        viewModel.dismissNotice()
    }

    /// Scrolls to the first focused question that is in the list and outlines all
    /// of them for a moment.
    @MainActor
    private func focusQuestionIfNeeded(_ proxy: ScrollViewProxy) async {
        let focusedIDs = focusedQuestionIDs.wrappedValue
        guard !focusedIDs.isEmpty else {
            return
        }

        let shownIDs = tabContent.shownQuestionIDs
        let questionIDs = focusedIDs.filter(shownIDs.contains)
        guard let firstID = questionIDs.first else {
            focusedQuestionIDs.wrappedValue = []
            return
        }

        withAnimation(PaeoniaMotion.stateChange) {
            proxy.scrollTo(firstID, anchor: .center)
            highlightedQuestionIDs = Set(questionIDs)
        }

        // Clearing the focused ids changes this task's id and cancels it, so keep
        // the ids until the highlight time is over.
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else {
            return
        }

        withAnimation(PaeoniaMotion.stateChange) {
            highlightedQuestionIDs.subtract(questionIDs)
            focusedQuestionIDs.wrappedValue = []
        }
    }
}

extension DailyChallengeScreen {
    @ViewBuilder
    func todayRow(_ row: QuestionsTabRow) -> some View {
        switch row {
        case .question(let question):
            DailyChallengeReadCard(
                question: question,
                participants: viewModel.participants,
                sending: viewModel.sendingPreview(for: question),
                zoomNamespace: zoomNamespace,
                isHighlighted: highlightedQuestionIDs.contains(question.id),
                onAnswer: { onAnswerPartnerQuestion(question) },
                lastMessagePreview: viewModel.threadPreview(for: question.questionID),
                hasUnreadChat: viewModel.hasUnreadChat(for: question.questionID),
                hasNewPartnerAnswer: (question.isCurrentDay || question.topicKey != nil)
                    && viewModel.hasNewPartnerAnswer(question),
                onOpen: { openChat(question, newest: viewModel.hasUnreadChat(for: question.questionID)) },
                topicTitle: topicsCard?.title(of: question)
            )
            .id(question.id)
        case .conversation(let conversation):
            SubjectConversationCard(conversation: conversation, people: storyPeople) {
                openConversation(conversation)
            }
        }
    }

    /// Earlier days, minus the questions today's list already shows.
    @ViewBuilder
    private var earlierDays: some View {
        if let historyViewModel {
            DailyChallengeEarlierDaysView(
                history: historyViewModel,
                viewModel: viewModel,
                conversations: ordinaryConversations.filter { !$0.isUnread },
                today: viewModel.snapshot.todayLocalDate,
                timeZone: viewModel.snapshot.timeZone,
                storyPeople: storyPeople,
                shownQuestionIDs: tabContent.shownQuestionIDs,
                onOpenChat: { openChat($0) },
                onOpenConversation: openConversation,
                onRetry: { Task { await historyViewModel.load() } }
            )
        }
    }

    /// Opens a memory's or a story's chat the same way: read from the phone first, then pushed.
    func openConversation(_ conversation: SubjectConversation) {
        if case let .game(game) = conversation.subject {
            chatContext.openGameChat?(game.kind, nil, nil)
            return
        }
        guard !isOpeningChat else { return }
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) { isOpeningChat = true }
        Task {
            guard let chat = await chatContext.makeViewModel(
                subject: conversation.summary.subject,
                header: conversation.header(people: storyPeople)
            ) else {
                isOpeningChat = false
                return
            }
            await Task.yield()
            conversationChat = ConversationChatDestination(conversation: conversation, viewModel: chat)
        }
    }

    private func openStoryAction(_ story: Story?) -> (() -> Void)? {
        guard let story, stories != nil else { return nil }
        return { storyViewer = StoryViewerContent(stories: [story], startIndex: 0, mode: .archive) }
    }

    private var isCalm: Bool {
        isDayComplete && tabContent.attention.isEmpty && topicsCard?.hook == nil
            && !(topicsCard?.shelfTopics.isEmpty ?? true)
    }

    /// Once today's challenge is answered, topic navigation stays above outstanding rows.
    /// Private topic details remain inside their topic.
    @ViewBuilder
    var topicsEntry: some View {
        if let topicsCard, topicsCard.isShown, !isCalm {
            TopicsCard(
                topics: topicsCard.topics,
                hook: topicsCard.hook,
                partnerName: viewModel.participants.partnerName,
                partnerPhotoAssetID: viewModel.participants.partnerProfilePhotoAssetID,
                onOpen: topicsCard.onOpen
            )
            .transition(.opacity)
        }
    }

    /// Every topic under today's list while the tab is calm.
    @ViewBuilder
    var topicsShelf: some View {
        if let topicsCard, topicsCard.isShown, isCalm {
            TopicsShelfSection(content: topicsCard)
                .transition(.opacity)
        }
    }
}

/// Keeps a tab's scroll view at its bottom inset with the tab bar showing, while the
/// bar is hidden. Otherwise the shorter safe area pulls a list scrolled to the end
/// down, and it stays there after the bar comes back.
private struct TabBarBottomInsetModifier: ViewModifier {
    let isTabBarHidden: Bool
    @State private var inset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, inset)
            .ignoresSafeArea(.container, edges: .bottom)
            .background {
                Color.clear.onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { newInset in
                    if !isTabBarHidden { inset = newInset }
                }
            }
    }
}

private extension View {
    func keepsTabBarBottomInset(whileHidden isHidden: Bool) -> some View {
        modifier(TabBarBottomInsetModifier(isTabBarHidden: isHidden))
    }
}
