import SwiftUI

/// The Questions tab: a calm overview of today's challenge. The hero card mirrors
/// the Us-tab prompt card and opens the focused answering flow (zooming into it).
/// Below it, every question — the user's own and the partner's — sits in one list:
/// questions still waiting for the user's answer are pinned on top so they're never
/// buried, then everything else follows by most recent answer. Most cards are
/// read-only; a partner question the user can still answer carries a CTA that zooms
/// into its single-question flow, where the reply is revealed on send. Answering
/// itself happens in the flow, never inline.
struct DailyChallengeScreen: View {
    let viewModel: DailyChallengeViewModel
    /// Namespace for the Daily Challenge zoom transition. The hero card and each
    /// answerable partner card mark themselves as zoom sources in it, so the tapped
    /// card appears to grow into its full-screen answer flow.
    var zoomNamespace: Namespace.ID?
    var focusedQuestionID: Binding<UUID?> = .constant(nil)
    var onOpenAnswerFlow: () -> Void = {}
    var onTapStreak: () -> Void = {}
    var onRefresh: (() async -> Void)?
    /// Opens the single-question answer flow for a partner-answered question.
    var onAnswerPartnerQuestion: (DailyChallengeQuestion) -> Void = { _ in }

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    /// The Questions history cover. Built fresh from the screen's view model when the
    /// History button is tapped, and presented by item so it carries its own state.
    @State private var historyViewModel: DailyChallengeHistoryViewModel?
    @State private var highlightedQuestionID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                    heroCard

                    if !readQuestions.isEmpty {
                        // One list for everything — the partner's questions and the user's
                        // own. Questions still waiting for you are pinned on top (so the
                        // actionable cards are never buried); everything else follows by most
                        // recent answer. A partner question you can still answer shows its
                        // CTA, locked until you finish your own three (answers saved locally
                        // and still sending count), matching the answer flow's gating; every
                        // other card is read-only. Answering one reveals the reply in the
                        // flow itself, so it's fine that the card then re-sorts down here.
                        VStack(spacing: PaeoniaSpacing.space12) {
                            ForEach(readQuestions) { question in
                                DailyChallengeReadCard(
                                    question: question,
                                    participants: viewModel.participants,
                                    sending: sendingPreview(for: question),
                                    isOwnChallengeComplete: viewModel.hasCompletedRequiredDailyQuestions,
                                    zoomNamespace: zoomNamespace,
                                    isHighlighted: highlightedQuestionID == question.id,
                                    onAnswer: { onAnswerPartnerQuestion(question) }
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
                .padding(.bottom, PaeoniaSpacing.space32)
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
        // The history cover carries its own loading and error state; it routes
        // recoverable errors into the same shared top banner.
        .fullScreenCover(item: $historyViewModel) { historyViewModel in
            DailyChallengeHistoryView(viewModel: historyViewModel, dailyChallengeViewModel: viewModel)
                .environment(bannerCenter)
        }
        .onChange(of: viewModel.notice) { _, notice in
            showBanner(for: notice)
        }
    }

    /// Every read card in one list — the partner's started questions plus the user's
    /// own answered (or still-sending) questions. The ordering (to-dos pinned on top,
    /// then by most recent answer) lives in `DailyChallengeSnapshot.readOverviewQuestions`.
    private var readQuestions: [DailyChallengeQuestion] {
        viewModel.snapshot.readOverviewQuestions.filter { question in
            question.origin == .partner || question.hasOwnAnswer || viewModel.isSending(question.id)
        }
    }

    /// Resolves the "saved, sending" preview for a question, or nil when it has
    /// already landed and reads from its revealed answer instead. Carries every part
    /// the answer holds, so a combined photo-plus-caption shows both while it sends.
    private func sendingPreview(for question: DailyChallengeQuestion) -> DailySendingPreview? {
        guard viewModel.isSending(question.id) else { return nil }
        return DailySendingPreview(
            mediaKind: question.mediaAnswerKind,
            mediaData: viewModel.sendingMediaData(for: question.id),
            voiceDurationMs: viewModel.sendingVoiceDurationMs(for: question.id),
            partnerChoiceName: viewModel.sendingPartnerChoiceName(for: question.id),
            text: viewModel.sendingText(for: question.id)
        )
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

        focusedQuestionID.wrappedValue = nil

        try? await Task.sleep(for: .seconds(2))
        guard highlightedQuestionID == questionID else {
            return
        }

        withAnimation(PaeoniaMotion.stateChange) {
            highlightedQuestionID = nil
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

actor PreviewDailyChallengeService: DailyChallengeServicing {
    static let userID = UUID()
    private let partnerUserID = UUID()

    func loadToday(currentUserID: UUID) async throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(
            snapshot: DailyChallengeSnapshot(
                currentUserID: currentUserID,
                coupleDayID: UUID(),
                questions: [
                    previewDailyQuestion(
                        slot: 1,
                        seededFor: currentUserID,
                        origin: .own,
                        prompt: "What small moment made you think of us today?",
                        short: "A small moment today"
                    ),
                    previewDailyQuestion(
                        slot: 2,
                        seededFor: currentUserID,
                        origin: .own,
                        prompt: "What's one thing you're looking forward to together?",
                        short: "Something to look forward to"
                    ),
                    previewDailyQuestion(
                        slot: 3,
                        seededFor: currentUserID,
                        origin: .own,
                        prompt: "Record a short goodnight message.",
                        short: "A short goodnight message",
                        answerKinds: [.voice, .text]
                    ),
                    previewDailyQuestion(
                        slot: 1,
                        seededFor: partnerUserID,
                        origin: .partner,
                        prompt: "What's a favourite memory of us from this month?",
                        short: "A favourite memory",
                        partnerAnswered: true
                    ),
                ],
                refreshedAt: .now
            ),
            streak: .none
        )
    }

    func startToday(currentUserID: UUID, operation _: SyncClientOperation) async throws -> DailyChallengeLoadResult {
        try await loadToday(currentUserID: currentUserID)
    }

    func loadHistory(currentUserID: UUID) async throws -> [DailyChallengeQuestion] {
        [
            previewHistoryQuestion(
                localDate: "2026-06-27",
                slot: 1,
                seededFor: currentUserID,
                prompt: "What small moment made you think of us today?",
                ownText: "Your text came up on my lock screen mid-meeting.",
                partnerText: "I saw a couple on the tram holding hands like we do."
            ),
            previewHistoryQuestion(
                localDate: "2026-06-26",
                slot: 1,
                seededFor: currentUserID,
                prompt: "What's one thing you're looking forward to together?",
                ownText: "The long weekend with nothing planned.",
                partnerText: "Cooking that pasta again, but slower this time."
            ),
            previewHistoryQuestion(
                localDate: "2026-06-26",
                slot: 2,
                seededFor: partnerUserID,
                prompt: "What made you laugh recently?",
                ownText: "Your voice note where you forgot what you were saying.",
                partnerText: "The dog video you sent at 1am."
            ),
        ]
    }

    func loadStreak() async throws -> CoupleStreak {
        CoupleStreak(
            currentCount: 6,
            longestCount: 12,
            lastQualifiedDate: "2026-06-26",
            restoreAvailable: false,
            restorableCount: 0,
            restoreDeadline: nil
        )
    }

    func submitAnswer(instanceID _: UUID, answerID _: UUID, payload _: DailyAnswerPayload, operation _: SyncClientOperation) async throws -> UUID {
        UUID()
    }

    func editTextAnswer(instanceID _: UUID, text _: String, operation _: SyncClientOperation) async throws -> UUID {
        UUID()
    }

    func editPartnerChoice(instanceID _: UUID, selectedUserID _: UUID, operation _: SyncClientOperation) async throws -> UUID {
        UUID()
    }

    func shuffleQuestion(
        currentUserID: UUID,
        slotNumber _: Int,
        operation _: SyncClientOperation
    ) async throws -> DailyChallengeLoadResult {
        try await loadToday(currentUserID: currentUserID)
    }
}

nonisolated func previewDailyQuestion(
    slot: Int,
    seededFor userID: UUID,
    origin: DailyQuestionOrigin,
    prompt: String,
    short: String,
    answerKinds: [DailyChallengeAnswerKind] = [.text],
    partnerAnswered: Bool = false
) -> DailyChallengeQuestion {
    DailyChallengeQuestion(
        id: UUID(),
        coupleDayID: UUID(),
        coupleID: UUID(),
        localDate: "2026-06-27",
        effectiveLocalDate: "2026-06-27",
        startsAt: .now,
        endsAt: .now.addingTimeInterval(86_400),
        seededForUserID: userID,
        slotNumber: slot,
        status: .active,
        questionID: UUID(),
        questionVersionID: UUID(),
        questionKey: "preview_question",
        prompt: prompt,
        shortPrompt: short,
        answerKinds: answerKinds,
        ownAnswer: nil,
        partnerAnswer: partnerAnswered ? DailyQuestionAnswerSummary(id: UUID(), answeredAt: .now) : nil,
        canViewPartnerAnswer: false,
        ownAnswerDetail: nil,
        partnerAnswerDetail: nil,
        origin: origin,
        isCurrentDay: true
    )
}

/// A fully-answered question for the history preview: both people answered with text
/// and both replies are revealed, so the read card shows a complete exchange.
nonisolated func previewHistoryQuestion(
    localDate: String,
    slot: Int,
    seededFor userID: UUID,
    prompt: String,
    ownText: String,
    partnerText: String,
    currentUserID: UUID = PreviewDailyChallengeService.userID
) -> DailyChallengeQuestion {
    let answeredAt = Date()
    let ownAnswerID = UUID()
    let partnerAnswerID = UUID()
    let partnerUserID = userID == currentUserID ? UUID() : userID

    return DailyChallengeQuestion(
        id: UUID(),
        coupleDayID: UUID(),
        coupleID: UUID(),
        localDate: localDate,
        effectiveLocalDate: localDate,
        startsAt: answeredAt,
        endsAt: answeredAt.addingTimeInterval(86_400),
        seededForUserID: userID,
        slotNumber: slot,
        status: .answered,
        questionID: UUID(),
        questionVersionID: UUID(),
        questionKey: "preview_history_question",
        prompt: prompt,
        shortPrompt: prompt,
        answerKinds: [.text],
        ownAnswer: DailyQuestionAnswerSummary(id: ownAnswerID, answeredAt: answeredAt),
        partnerAnswer: DailyQuestionAnswerSummary(id: partnerAnswerID, answeredAt: answeredAt),
        canViewPartnerAnswer: true,
        ownAnswerDetail: DailyQuestionAnswerDetail(
            answerUserID: currentUserID,
            answerID: ownAnswerID,
            answeredAt: answeredAt,
            isOwnAnswer: true,
            canViewAnswer: true,
            textBody: ownText,
            selectedUserID: nil,
            mediaAssetIDs: []
        ),
        partnerAnswerDetail: DailyQuestionAnswerDetail(
            answerUserID: partnerUserID,
            answerID: partnerAnswerID,
            answeredAt: answeredAt,
            isOwnAnswer: false,
            canViewAnswer: true,
            textBody: partnerText,
            selectedUserID: nil,
            mediaAssetIDs: []
        ),
        origin: userID == currentUserID ? .own : .partner,
        isCurrentDay: false
    )
}
#endif
