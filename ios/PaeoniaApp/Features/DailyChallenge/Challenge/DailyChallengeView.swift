import SwiftUI

/// The Questions tab: a calm overview of today's challenge. The hero card mirrors
/// the Us-tab prompt card and opens the focused answering flow (zooming into it).
/// Below it, every question — the user's own and the partner's — sits in one list:
/// questions still waiting for the user's answer are pinned on top so they're never
/// buried, then everything else follows by most recent answer. The rows hold no
/// answers. A row the user has answered opens the question's page, where the answers
/// start the chat. A partner question the user can still answer zooms into its
/// single-question flow, where the reply is revealed on send.
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
    /// Opens a chat by question id, for unread chats on questions from earlier days.
    var onOpenUnreadChat: (UUID) -> Void = { _ in }
    var privacySafetyService: (any PrivacySafetyServicing)?
    var privacyOperationProvider: (any SyncClientOperationProviding)?
    var onReportedAndLeft: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    /// The Questions history cover. Built fresh from the screen's view model when the
    /// History button is tapped, and presented by item so it carries its own state.
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
                    earlierUnreadChatsCard

                    if !readQuestions.isEmpty {
                        // One list for everything — the partner's questions and the user's
                        // own. Questions still waiting for you are pinned on top, then cards
                        // with a partner answer or message you haven't seen (so nothing new
                        // is buried); everything else follows by most recent answer. A
                        // partner question you can still answer opens its flow, locked until
                        // you finish your own three (answers saved locally and still sending
                        // count), matching the answer flow's gating. A row
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
                                    lastMessagePreview: viewModel.threadPreview(for: question.id),
                                    hasUnreadChat: viewModel.hasUnreadChat(for: question.id),
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
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
                .padding(.bottom, PaeoniaSpacing.space32)
                .paeoniaReadableWidth(alignment: .leading)
            }
            .refreshable {
                if let onRefresh {
                    await onRefresh()
                } else {
                    await viewModel.reload()
                }
            }
            .task(id: focusedQuestionID.wrappedValue) {
                await focusQuestionIfNeeded(proxy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.mainTabQuestions))
        .toolbar(chatQuestion.wrappedValue != nil || isOpeningChat ? .hidden : .visible, for: .tabBar)
        .onChange(of: chatQuestion.wrappedValue == nil) { _, isClosed in
            if isClosed { isOpeningChat = false }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The streak sits just before the History button, sized to match the brand
            // mark and carried in the toolbar's standard background.
            if streakPill.isVisible {
                ToolbarItem(placement: .topBarTrailing) {
                    DailyStreakToolbarLabel(state: streakPill, onTap: onTapStreak)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    historyViewModel = viewModel.makeHistoryViewModel()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel(Text(.dailyChallengeHistoryButton))
            }
        }
        // The history cover carries its own loading and error state. It routes
        // recoverable errors into the shared top banner, which the cover draws on top.
        .fullScreenCover(item: $historyViewModel) { historyViewModel in
            DailyChallengeHistoryView(
                viewModel: historyViewModel,
                dailyChallengeViewModel: viewModel,
                privacySafetyService: privacySafetyService,
                privacyOperationProvider: privacyOperationProvider,
                onReportedAndLeft: onReportedAndLeft
            )
            .environment(bannerCenter)
            .paeoniaTopBanner(bannerCenter)
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

    /// Every read card in one list — the partner's started questions plus the user's
    /// own answered (or still-sending) questions. The ordering (to-dos, then anything
    /// new from the partner, then by most recent answer) lives in
    /// `DailyChallengeSnapshot.readOverviewQuestions`.
    private var readQuestions: [DailyChallengeQuestion] {
        viewModel.snapshot.readOverviewQuestions(isNew: viewModel.hasNewFromPartner).filter { question in
            question.origin == .partner || question.hasOwnAnswer || viewModel.isSending(question.id)
        }
    }

    /// The tab badge counts every unread chat, but the list below the hero only
    /// holds today's questions. Unread chats from earlier days show here instead.
    @ViewBuilder
    private var earlierUnreadChatsCard: some View {
        let shownIDs = Set(readQuestions.map(\.id))
        let chats = viewModel.unreadChats
            .filter { !shownIDs.contains($0.instanceID) }
            .map { UnreadChatRow(id: $0.instanceID, prompt: nil, preview: $0.lastMessagePreview) }
        if !chats.isEmpty {
            HomeUnreadChatsCard(
                chats: chats,
                partnerName: viewModel.participants.partnerName,
                partnerProfilePhotoAssetID: viewModel.participants.partnerProfilePhotoAssetID,
                onOpenChat: onOpenUnreadChat
            )
        }
    }

    /// The couple's streak for the toolbar badge — derived from the live server streak.
    private var streakPill: StreakPillState {
        StreakPillState(viewModel.streak)
    }

    private var heroCard: some View {
        DailyPromptCard(
            state: viewModel.homeCardState,
            partnerName: viewModel.participants.partnerName,
            onAnswer: onOpenAnswerFlow
        )
        .zoomSource(DailyFlowZoom.questions, in: zoomNamespace)
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
