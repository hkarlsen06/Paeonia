import SwiftUI

/// Unanswered partner questions stay above the activity-ordered conversations.
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
    /// Keeps the hero card up after today's answer until its seal moment has played, so
    /// the answer flow it opened zooms back into it. Armed when the card opens the flow.
    @State private var heroHold = DailyPromptCardHold()

    private var isChatOpen: Bool {
        chatQuestion.wrappedValue != nil || conversationChat != nil
    }

    private var hidesTabBar: Bool {
        isChatOpen || isOpeningChat
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                screenContent
                // Sections and rows fade in and out, and the rest glides to its new place.
                .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: sectionLayout)
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
        // A new day drops a hold from a flow that closed without an answer.
        .onChange(of: viewModel.homeCardState) { _, state in
            if state.kind == .noChallenge { heroHold.release() }
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

    private var screenContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
            coupleChatCard
            waitingSection
            heroCard
            topicsEntry
            topicsShelf
            activeGameChats
            conversationSection
            historyStatus
        }
    }

    /// The couple's streak for the toolbar badge — derived from the live server streak.
    private var streakPill: StreakPillState {
        StreakPillState(viewModel.streak)
    }

    /// Whether the screen shows today's question as answered. The big card then gives way
    /// to the conversation card for that question. Right after the answer, the screen
    /// keeps the big card until its seal moment has played.
    private var isDayComplete: Bool {
        viewModel.homeCardState.kind == .complete && !isHoldingHero
    }

    var isHoldingHero: Bool {
        heroHold.isHolding(for: viewModel.homeCardState)
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
                onAnswer: {
                    heroHold.observe(viewModel.homeCardState)
                    onOpenAnswerFlow()
                },
                onMomentEnd: finishHeroMoment
            )
            .zoomSource(DailyFlowZoom.questions, in: zoomNamespace)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
        }
    }

    /// The seal moment is over. The card folds away and today's question row, now in the
    /// list, lights up for a moment so the person sees where the conversation went.
    private func finishHeroMoment() {
        heroHold.release()
        guard isDayComplete, let todayID = viewModel.snapshot.todayQuestion?.id else { return }
        focusedQuestionIDs.wrappedValue = [todayID]
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

        let shownIDs = Set((tabContent.waitingForYou + tabContent.recent).map(\.id))
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
                lastMessagePreview: viewModel.conversationPreview(for: question),
                activityDate: question.conversationActivityDate(
                    messageDate: viewModel.threadSummary(for: question.questionID)?.lastMessageAt
                ),
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

    @ViewBuilder
    private var historyStatus: some View {
        if let historyViewModel {
            switch historyViewModel.state {
            case .loading:
                ProgressView().tint(.paeoniaAccentPrimary).frame(maxWidth: .infinity)
            case .failed(let failure):
                PaeoniaLoadFailureView(failure: failure, offlineMessage: .dailyChallengeHistoryLoadFailedMessage) {
                    Button { Task { await historyViewModel.load() } } label: {
                        Text(.dailyChallengeHistoryRetryButton)
                    }
                    .buttonStyle(PaeoniaPrimaryButtonStyle())
                }
            case .empty, .content:
                EmptyView()
            }
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

    /// Everything that adds, removes or moves a section or a row, such as the hero
    /// shrinking to one row. The screen animates on it as a whole.
    var sectionLayout: ChatsSectionLayout {
        ChatsSectionLayout(
            isDayComplete: isDayComplete,
            isCalm: isCalm,
            waiting: waitingRows.map(\.id),
            recent: tabContent.recent.map(\.id),
            quietGames: quietGameKinds,
            history: historyViewModel.map { ChatsSectionLayout.HistoryStatus($0.state) }
        )
    }

    private var isCalm: Bool {
        isDayComplete && tabContent.waitingForYou.isEmpty && topicsCard?.hook == nil
            && !(topicsCard?.shelfTopics.isEmpty ?? true)
    }

    /// Topics remain reachable above the full conversation history, below unanswered questions.
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

    /// Every topic below the daily prompt while the tab is calm.
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
