import SwiftUI

/// The Questions tab: a calm overview of today's challenge. The hero card mirrors
/// the Us-tab prompt card and opens the focused answering flow (zooming into it);
/// the sections below are read-only — they show what has already been shared today
/// and your partner's answers, including the locked ones that reveal once you reply.
/// Answering itself happens in `DailyChallengeAnswerFlow`, never inline here.
struct DailyChallengeScreen: View {
    let viewModel: DailyChallengeViewModel
    var morphNamespace: Namespace.ID?
    /// Namespace for the per-card partner-answer morph; the parent passes it only
    /// while collapsed (and not under Reduce Motion) so the tapped card's CTA glides
    /// into the answer flow.
    var partnerMorphNamespace: Namespace.ID?
    var onOpenAnswerFlow: () -> Void = {}
    var onTapStreak: () -> Void = {}
    /// Opens the single-question answer flow for a partner-answered question.
    var onAnswerPartnerQuestion: (DailyChallengeQuestion) -> Void = { _ in }

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    /// The card order is captured once per visit and held steady while the tab stays
    /// open, so answering a question (which changes its sort position) doesn't yank
    /// the card out from under the user — it stays put, with the partner's reply now
    /// revealed in place. The order only refreshes on a full re-entry of the tab.
    @State private var frozenPartnerOrder: [UUID] = []
    @State private var frozenOwnOrder: [UUID] = []
    @State private var hasFrozenOrder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                heroCard

                if !partnerReadQuestions.isEmpty {
                    DailyChallengeReadSection(
                        title: .dailyChallengePartnerSectionTitle,
                        questions: partnerReadQuestions,
                        participants: viewModel.participants,
                        sendingPreview: { sendingPreview(for: $0) },
                        // Partner questions can only be answered once the user has
                        // finished their own three, including answers saved locally
                        // and still sending.
                        isOwnChallengeComplete: viewModel.hasCompletedRequiredDailyQuestions,
                        morphNamespace: partnerMorphNamespace,
                        onAnswer: onAnswerPartnerQuestion
                    )
                }

                if !ownReadQuestions.isEmpty {
                    DailyChallengeReadSection(
                        title: .dailyChallengeOwnSectionTitle,
                        questions: ownReadQuestions,
                        participants: viewModel.participants,
                        sendingPreview: { sendingPreview(for: $0) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
        }
        .background(.paeoniaBackgroundPrimary)
        .refreshable {
            await viewModel.reload()
        }
        .navigationTitle(Text(.mainTabQuestions))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.notice) { _, notice in
            showBanner(for: notice)
        }
        // Capture the order on entry, and again if data arrives just after; a full
        // re-entry of the tab (leaving and coming back) clears it so it re-sorts.
        .onAppear { freezeOrderIfNeeded() }
        .onChange(of: viewModel.snapshot) { _, _ in freezeOrderIfNeeded() }
        .onDisappear { hasFrozenOrder = false }
    }

    /// Partner-started questions surface first, with unanswered bonus replies at
    /// the top so they are easy to find once the user's three are done. Held in the
    /// order captured on entry so answering one doesn't make it jump away.
    private var partnerReadQuestions: [DailyChallengeQuestion] {
        stableOrdered(viewModel.snapshot.partnerQuestionsForReadOverview, frozen: frozenPartnerOrder)
    }

    /// Own questions surface once answered or locally sending. Rows where the
    /// partner has replied come before rows still waiting on the partner. Held in the
    /// order captured on entry.
    private var ownReadQuestions: [DailyChallengeQuestion] {
        let current = viewModel.snapshot.ownQuestionsForReadOverview.filter {
            $0.hasOwnAnswer || viewModel.isSending($0.id)
        }
        return stableOrdered(current, frozen: frozenOwnOrder)
    }

    /// Reorders the freshly-sorted `current` list to the order captured on entry,
    /// keeping any questions that have since appeared at the end. Before the order is
    /// frozen it returns `current` unchanged.
    private func stableOrdered(
        _ current: [DailyChallengeQuestion],
        frozen: [UUID]
    ) -> [DailyChallengeQuestion] {
        guard hasFrozenOrder else { return current }
        let byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let frozenSet = Set(frozen)
        return frozen.compactMap { byID[$0] } + current.filter { !frozenSet.contains($0.id) }
    }

    /// Snapshots the current sort order once data is available. Skips if already
    /// frozen this visit, or if there's nothing to capture yet (so the real order is
    /// taken once questions have loaded, not while empty).
    private func freezeOrderIfNeeded() {
        guard !hasFrozenOrder else { return }
        let partner = viewModel.snapshot.partnerQuestionsForReadOverview
        let own = viewModel.snapshot.ownQuestionsForReadOverview
        guard !partner.isEmpty || !own.isEmpty else { return }
        frozenPartnerOrder = partner.map(\.id)
        frozenOwnOrder = own.map(\.id)
        hasFrozenOrder = true
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

    private var heroCard: some View {
        DailyPromptCard(
            state: viewModel.homeCardState,
            streak: StreakPillState(viewModel.streak),
            morphNamespace: morphNamespace,
            onAnswer: onOpenAnswerFlow,
            onTapStreak: onTapStreak
        )
    }

    private func showBanner(for notice: DailyChallengeViewModel.Notice?) {
        guard let notice else { return }
        bannerCenter.show(
            .error(
                title: String(localized: notice.title),
                message: String(localized: notice.message)
            )
        )
        viewModel.dismissNotice()
    }
}

/// A "saved, sending" answer to keep visible in the read overview while it finishes
/// sending: a photo/voice note plays from its staged bytes, a partner pick and/or text
/// caption show what was chosen or written. Any combination can be present.
private struct DailySendingPreview {
    var mediaKind: DailyChallengeAnswerKind = .photo
    var mediaData: Data?
    var voiceDurationMs: Int?
    var partnerChoiceName: String?
    var text: String?
}

private struct DailyChallengeReadSection: View {
    let title: LocalizedStringResource
    let questions: [DailyChallengeQuestion]
    var participants = DailyChallengeParticipants()
    /// Resolves a question's "saved, sending" preview; partner sections leave this at
    /// its default since only the current user's own answers send from this device.
    var sendingPreview: (DailyChallengeQuestion) -> DailySendingPreview? = { _ in nil }
    /// Whether the user has finished their own three questions. Until then a partner
    /// question's CTA is locked. Defaults to true so the own section is unaffected.
    var isOwnChallengeComplete = true
    /// Partner-answer morph namespace and tap handler; both default to off so the own
    /// section (which never offers an answer CTA) is unaffected.
    var morphNamespace: Namespace.ID?
    var onAnswer: (DailyChallengeQuestion) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(title)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)

            VStack(spacing: PaeoniaSpacing.space12) {
                ForEach(questions) { question in
                    DailyChallengeReadCard(
                        question: question,
                        participants: participants,
                        sending: sendingPreview(question),
                        isOwnChallengeComplete: isOwnChallengeComplete,
                        morphNamespace: morphNamespace,
                        onAnswer: { onAnswer(question) }
                    )
                }
            }
        }
    }
}

private struct DailyChallengeReadCard: View {
    let question: DailyChallengeQuestion
    var participants = DailyChallengeParticipants()
    var sending: DailySendingPreview?
    var isOwnChallengeComplete = true
    var morphNamespace: Namespace.ID?
    var onAnswer: () -> Void = {}

    /// A partner question the user can still answer to reveal the reply. When sending,
    /// the card shows the "saved, sending" preview instead, so this stays false.
    private var isAnswerable: Bool {
        sending == nil && question.origin == .partner && question.isAvailableToAnswer
    }

    /// Whether tapping the CTA can actually open the answer flow. Answering a
    /// partner's question is gated behind finishing your own three first, so until
    /// then the CTA is shown but locked (and doesn't morph into the flow).
    private var canOpenAnswerFlow: Bool {
        isAnswerable && isOwnChallengeComplete
    }

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                Text(question.prompt)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Cards that can open the flow morph their question into it;
                    // locked cards stay put since tapping does nothing yet.
                    .dailyChallengeMorph(
                        DailyChallengeMorph.partnerAnswerPrompt(question.id),
                        in: canOpenAnswerFlow ? morphNamespace : nil
                    )

                if let sending {
                    // Still saving: shows whatever was saved (photo, pick, and/or
                    // caption), so the usual "not answered" status would only contradict it.
                    DailySendingAnswerView(
                        mediaKind: sending.mediaKind,
                        mediaData: sending.mediaData,
                        voiceDurationMs: sending.voiceDurationMs,
                        partnerChoiceName: sending.partnerChoiceName,
                        text: sending.text
                    )
                } else {
                    DailyQuestionStatusView(question: question)

                    if isAnswerable {
                        // The CTA itself carries the call to action (answer to reveal,
                        // or finish your own first), so no extra explanatory line.
                        answerButton
                    } else {
                        DailyAnswerDetailsView(question: question, participants: participants)
                    }
                }
            }
        }
    }

    /// The same primary CTA the daily prompt card uses. When the user still has their
    /// own questions to finish it stays visible but disabled, so it reads as a clear
    /// "do yours first" rather than disappearing. Once unlocked it carries this
    /// question's morph id so tapping it expands the card into the answer flow.
    private var answerButton: some View {
        Button(action: onAnswer) {
            Text(canOpenAnswerFlow ? .dailyChallengePartnerAnswerCta : .dailyChallengePartnerLockedCta)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!canOpenAnswerFlow)
        .dailyChallengeMorph(
            DailyChallengeMorph.partnerAnswerButton(question.id),
            in: canOpenAnswerFlow ? morphNamespace : nil
        )
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

    func loadToday(currentUserID: UUID) async throws -> DailyChallengeSnapshot {
        DailyChallengeSnapshot(
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
        )
    }

    func startToday(currentUserID: UUID, operation _: SyncClientOperation) async throws -> DailyChallengeSnapshot {
        try await loadToday(currentUserID: currentUserID)
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
    ) async throws -> DailyChallengeSnapshot {
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
        origin: origin
    )
}
#endif
