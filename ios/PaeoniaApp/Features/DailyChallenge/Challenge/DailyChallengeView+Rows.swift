import SwiftUI

extension DailyChallengeScreen {
    var tabContent: QuestionsTabContent {
        // The hero card stands for today's question until its seal moment ends.
        let heldID = isHoldingHero ? viewModel.snapshot.todayQuestion?.id : nil
        let current = viewModel.snapshot.questions.filter {
            ($0.hasOwnAnswer || viewModel.isSending($0.id) || $0.isAwaitingCurrentUserAnswer) && $0.id != heldID
        }
        return QuestionsTabContent(
            current: current,
            topics: topicsCard?.waitingQuestions ?? [],
            history: (historyViewModel?.questions ?? []).filter { $0.id != heldID },
            conversations: ordinaryConversations,
            messageDate: { viewModel.threadSummary(for: $0.questionID)?.lastMessageAt }
        )
    }

    var waitingRows: [QuestionsTabRow] {
        tabContent.waitingForYou.filter { row in
            guard case .question(let question) = row else { return true }
            return question.id != viewModel.snapshot.todayQuestion?.id || viewModel.homeCardState.kind == .complete
        }
    }

    @ViewBuilder
    var waitingSection: some View {
        if !waitingRows.isEmpty {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                Text(.chatsWaitingForYou)
                    .font(PaeoniaTypography.sectionTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                // A few rows, so no lazy stack. A lazy one fading out with the section
                // draws the recent list's first row in its place.
                ForEach(waitingRows) { todayRow($0) }
            }
        }
    }

    @ViewBuilder
    var conversationSection: some View {
        if !tabContent.recent.isEmpty {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                Text(.chatsRecentConversations)
                    .font(PaeoniaTypography.sectionTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                LazyVStack(spacing: PaeoniaSpacing.space12) {
                    ForEach(tabContent.recent) { todayRow($0) }
                }
                // Lazy rows sit in the scroll view's space. Without the group, a section that
                // glides moves its rows twice, so they start a section's height out of place.
                .geometryGroup()
            }
        }
    }
}

struct ChatsSectionLayout: Equatable {
    enum HistoryStatus: Equatable {
        case loading
        case failed
        case done

        init(_ state: DailyChallengeHistoryViewModel.ViewState) {
            switch state {
            case .loading: self = .loading
            case .failed: self = .failed
            case .empty, .content: self = .done
            }
        }
    }

    let isDayComplete: Bool
    let isCalm: Bool
    let waiting: [UUID]
    let recent: [UUID]
    let quietGames: [GameKind]
    let history: HistoryStatus?
}
