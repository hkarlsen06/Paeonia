import SwiftUI

/// The Questions tab: a calm overview of today's challenge. The hero card mirrors
/// the Us-tab prompt card and opens the focused answering flow (zooming into it);
/// the sections below are read-only — they show what has already been shared today
/// and your partner's answers, including the locked ones that reveal once you reply.
/// Answering itself happens in `DailyChallengeAnswerFlow`, never inline here.
struct DailyChallengeScreen: View {
    let viewModel: DailyChallengeViewModel
    var morphNamespace: Namespace.ID?
    var onOpenAnswerFlow: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                heroCard

                if !answeredOwnQuestions.isEmpty {
                    DailyChallengeReadSection(
                        title: .dailyChallengeOwnSectionTitle,
                        questions: answeredOwnQuestions,
                        participants: viewModel.participants
                    )
                }

                if !viewModel.snapshot.partnerStartedQuestions.isEmpty {
                    DailyChallengeReadSection(
                        title: .dailyChallengePartnerSectionTitle,
                        questions: viewModel.snapshot.partnerStartedQuestions,
                        participants: viewModel.participants
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
    }

    private var answeredOwnQuestions: [DailyChallengeQuestion] {
        viewModel.snapshot.ownQuestions.filter(\.hasOwnAnswer)
    }

    private var heroCard: some View {
        DailyPromptCard(
            state: viewModel.homeCardState,
            morphNamespace: morphNamespace,
            onAnswer: onOpenAnswerFlow
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

private struct DailyChallengeReadSection: View {
    let title: LocalizedStringResource
    let questions: [DailyChallengeQuestion]
    var participants = DailyChallengeParticipants()

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(title)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)

            VStack(spacing: PaeoniaSpacing.space12) {
                ForEach(questions) { question in
                    DailyChallengeReadCard(question: question, participants: participants)
                }
            }
        }
    }
}

private struct DailyChallengeReadCard: View {
    let question: DailyChallengeQuestion
    var participants = DailyChallengeParticipants()

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                Text(question.prompt)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                DailyQuestionStatusView(question: question)

                DailyAnswerDetailsView(question: question, participants: participants)
            }
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
