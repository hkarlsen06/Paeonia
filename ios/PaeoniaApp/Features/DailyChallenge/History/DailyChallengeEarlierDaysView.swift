import SwiftUI

/// The earlier days under today's list on the Questions tab: a centered date divider per
/// day, then the day's question rows, newest day first. A row the user has answered opens
/// the question's page. Questions that today's list already shows are left out, so each
/// one appears once. The first load shows a spinner, and a failed first load shows a retry
/// button. A failed reload keeps the days and raises a banner instead.
struct DailyChallengeEarlierDaysView: View {
    let history: DailyChallengeHistoryViewModel
    let viewModel: DailyChallengeViewModel
    /// The questions today's list shows. They are not repeated here.
    let shownQuestionIDs: Set<UUID>
    var onOpenChat: (DailyChallengeQuestion) -> Void = { _ in }
    var onRetry: () -> Void = {}

    var body: some View {
        Group {
            switch history.state {
            case .loading:
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PaeoniaSpacing.space16)
            case .failed(let failure):
                failedState(failure)
            case .empty:
                EmptyView()
            case .content:
                days
            }
        }
        .animation(PaeoniaMotion.stateChange, value: history.state)
    }

    private var days: some View {
        LazyVStack(spacing: PaeoniaSpacing.sectionSpacing) {
            ForEach(history.days(excluding: shownQuestionIDs)) { day in
                VStack(spacing: PaeoniaSpacing.space12) {
                    DailyChallengeHistoryDateDivider(date: day.date)

                    ForEach(day.questions) { question in
                        DailyChallengeReadCard(
                            question: question,
                            participants: viewModel.participants,
                            lastMessagePreview: viewModel.threadPreview(for: question.questionID),
                            hasUnreadChat: viewModel.hasUnreadChat(for: question.questionID),
                            hasNewPartnerAnswer: viewModel.hasNewPartnerAnswer(question),
                            onOpen: { onOpenChat(question) }
                        )
                    }
                }
            }
        }
    }

    private func failedState(_ failure: PaeoniaFailure) -> some View {
        PaeoniaEmptyStateView(
            title: .dailyChallengeHistoryLoadFailedTitle,
            message: failure.dailyHistoryMessage,
            systemImage: "exclamationmark.triangle"
        ) {
            VStack(spacing: PaeoniaSpacing.space8) {
                Button(action: onRetry) {
                    Text(.dailyChallengeHistoryRetryButton)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                if failure == .other {
                    PaeoniaSupportLink()
                }
            }
        }
    }
}
