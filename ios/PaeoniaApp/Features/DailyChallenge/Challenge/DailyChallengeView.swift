import SwiftUI

/// The Questions tab: a calm overview of today's challenge. The hero card mirrors
/// the Home tab prompt card and opens the focused answering flow (zooming into it).
/// Once the user has answered today's questions it shrinks to a one-row card.
/// Below it, every question — the user's own and the partner's — sits in one list:
/// questions still waiting for the user's answer are pinned on top so they're never
/// buried, then everything else follows by most recent answer. The rows hold no
/// answers. A row the user has answered opens the question's page, where the answers
/// start the chat. A partner question the user can still answer zooms into its
/// single-question flow, where the reply is revealed on send. Earlier days follow
/// under today's list, with a date divider per day.
struct DailyChallengeScreen: View {
    let viewModel: DailyChallengeViewModel
    /// Namespace for the Daily Challenge zoom transition. The hero card and each
    /// answerable partner card mark themselves as zoom sources in it, so the tapped
    /// card appears to grow into its full-screen answer flow.
    var zoomNamespace: Namespace.ID?
    var focusedQuestionID: Binding<UUID?> = .constant(nil)
    var chatQuestion: Binding<DailyChallengeQuestion?> = .constant(nil)
    var onOpenAnswerFlow: () -> Void = {}
    var onTapStreak: () -> Void = {}
    var onRefresh: (() async -> Void)?
    /// Opens the single-question answer flow for a partner-answered question.
    var onAnswerPartnerQuestion: (DailyChallengeQuestion) -> Void = { _ in }
    var privacySafetyService: (any PrivacySafetyServicing)?
    var privacyOperationProvider: (any SyncClientOperationProviding)?
    var onReportedAndLeft: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The earlier days under today's list. Built once the signed-in user is known, and
    /// kept while a chat is open on top of this screen.
    @State private var historyViewModel: DailyChallengeHistoryViewModel?
    @State private var highlightedQuestionID: UUID?
    @State private var reportTarget: PrivacyReportTarget?
    /// Hides the tab bar while a chat is about to open, before the push starts. Hiding
    /// it from the pushed chat instead would bring it back only after the back swipe
    /// ends. Same approach as Tidex's chat.
    @State private var isOpeningChat = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                    heroCard

                    todayList

                    earlierDays
                }
                // The hero shrinking to one row moves everything under it with a glide.
                .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: isDayComplete)
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
                .padding(.bottom, PaeoniaSpacing.space32)
                .paeoniaReadableWidth(alignment: .leading)
            }
            .refreshable { await refresh() }
            .task(id: focusedQuestionID.wrappedValue) {
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
        .paeoniaScreenBackground()
        .clearsDeliveredQuestionTimeReminders()
        .navigationTitle(Text(.mainTabQuestions))
        .toolbar(chatQuestion.wrappedValue != nil || isOpeningChat ? .hidden : .visible, for: .tabBar)
        .onChange(of: chatQuestion.wrappedValue == nil) { _, isClosed in
            if isClosed { isOpeningChat = false }
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
            DailyQuestionChatView(
                viewModel: viewModel.makeChatViewModel(question: question),
                question: viewModel.latestQuestion(question),
                participants: viewModel.participants,
                onReport: { reportTarget = $0 }
            )
            .id(question.id)
        }
        .onChange(of: viewModel.notice) { _, notice in
            showBanner(for: notice)
        }
    }

    /// Today's questions in one list.
    @ViewBuilder
    private var todayList: some View {
        if !readQuestions.isEmpty {
            // One list for everything — the partner's questions and the user's
            // own. Questions still waiting for you are pinned on top, then cards
            // with a partner answer or message you haven't seen (so nothing new
            // is buried); everything else follows by most recent answer. A
            // partner question you can still answer opens its flow, locked until
            // you finish your own questions (answers saved locally and still
            // sending count), matching the answer flow's gating. A row
            // you have answered opens the question's page with the answers and
            // the chat. Answering reveals the reply in the flow itself, so it's
            // fine that the row then re-sorts down here.
            VStack(spacing: PaeoniaSpacing.space12) {
                ForEach(readQuestions) { question in
                    DailyChallengeReadCard(
                        question: question,
                        participants: viewModel.participants,
                        sending: viewModel.sendingPreview(for: question),
                        isOwnChallengeComplete: viewModel.hasCompletedRequiredDailyQuestions,
                        zoomNamespace: zoomNamespace,
                        isHighlighted: highlightedQuestionID == question.id,
                        onAnswer: { onAnswerPartnerQuestion(question) },
                        lastMessagePreview: viewModel.threadPreview(for: question.questionID),
                        hasUnreadChat: viewModel.hasUnreadChat(for: question.questionID),
                        hasNewPartnerAnswer: viewModel.hasNewPartnerAnswer(question),
                        onOpen: { openChat(question) }
                    )
                    .id(question.id)
                }
            }
            // A refreshed snapshot re-sorts, adds, or removes cards with
            // a glide instead of reflowing the list in one frame — e.g.
            // an answered partner question settling down into the
            // timeline, or a new card arriving mid-session.
            .animation(PaeoniaMotion.stateChange, value: readQuestions.map(\.id))
        }
    }

    /// Every read card in one list — the partner's started questions plus the user's
    /// own answered (or still-sending) questions. The ordering (to-dos, then anything
    /// new from the partner, then by most recent answer) lives in
    /// `DailyChallengeSnapshot.readOverviewQuestions`.
    private var readQuestions: [DailyChallengeQuestion] {
        viewModel.snapshot.readOverviewQuestions(isNew: viewModel.hasNewFromPartner).filter { question in
            question.origin == .partner || question.hasOwnAnswer || viewModel.isSending(question.id)
        }
    }

    /// Earlier days, minus the questions today's list already shows.
    @ViewBuilder
    private var earlierDays: some View {
        if let historyViewModel {
            DailyChallengeEarlierDaysView(
                history: historyViewModel,
                viewModel: viewModel,
                shownQuestionIDs: Set(readQuestions.map(\.id)),
                onOpenChat: openChat,
                onRetry: { Task { await historyViewModel.load() } }
            )
        }
    }

    /// The couple's streak for the toolbar badge — derived from the live server streak.
    private var streakPill: StreakPillState {
        StreakPillState(viewModel.streak)
    }

    /// Whether the user has answered today's questions. The big card then gives way to
    /// the one-row card, which opens the same flow to review the user's answers.
    private var isDayComplete: Bool {
        viewModel.homeCardState.kind == .complete
    }

    private var heroCard: some View {
        let state = viewModel.homeCardState
        return Group {
            if state.kind == .complete {
                DailyChallengeDoneCard(
                    state: state,
                    partnerName: viewModel.participants.partnerName,
                    partnerPhotoAssetID: viewModel.participants.partnerProfilePhotoAssetID,
                    onOpen: onOpenAnswerFlow,
                    onOpenPartnerQuestion: openLockedPartnerQuestion
                )
                .transition(.opacity)
            } else {
                DailyPromptCard(
                    state: state,
                    partnerName: viewModel.participants.partnerName,
                    partnerPhotoAssetID: viewModel.participants.partnerProfilePhotoAssetID,
                    onAnswer: onOpenAnswerFlow,
                    onOpenPartnerQuestion: openLockedPartnerQuestion
                )
                .transition(.opacity)
            }
        }
        .zoomSource(DailyFlowZoom.questions, in: zoomNamespace)
    }

    /// A locked row on the hero card opens the same single-question flow as the
    /// question's own row in the list below.
    private func openLockedPartnerQuestion(_ id: UUID) {
        guard let question = viewModel.snapshot.questions.first(where: { $0.id == id }) else { return }
        onAnswerPartnerQuestion(question)
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
    private func openChat(_ question: DailyChallengeQuestion) {
        guard !isOpeningChat else { return }
        isOpeningChat = true
        Task {
            await viewModel.prepareChat(for: question)
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

    @MainActor
    private func focusQuestionIfNeeded(_ proxy: ScrollViewProxy) async {
        guard let questionID = focusedQuestionID.wrappedValue else {
            return
        }

        guard readQuestions.contains(where: { $0.id == questionID }) else {
            focusedQuestionID.wrappedValue = nil
            return
        }

        withAnimation(PaeoniaMotion.stateChange) {
            proxy.scrollTo(questionID, anchor: .center)
            highlightedQuestionID = questionID
        }

        // Clearing the focused id changes this task's id and cancels it, so keep
        // the id until the highlight time is over.
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else {
            return
        }

        withAnimation(PaeoniaMotion.stateChange) {
            if highlightedQuestionID == questionID {
                highlightedQuestionID = nil
            }
            focusedQuestionID.wrappedValue = nil
        }
    }
}

#if DEBUG
#Preview {
    DailyChallengeScreenPreviewHost()
}

private struct DailyChallengeScreenPreviewHost: View {
    @State private var viewModel = DailyChallengeViewModel(service: PreviewDailyChallengeService())

    var body: some View {
        NavigationStack {
            DailyChallengeScreen(viewModel: viewModel)
        }
        .environment(PaeoniaBannerCenter())
        .preferredColorScheme(.dark)
        .task {
            await viewModel.configure(currentUserID: PreviewDailyChallengeService.userID)
        }
    }
}
#endif
