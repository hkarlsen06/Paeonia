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
                rowsList(waitingRows)
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
                rowsList(tabContent.recent)
            }
        }
    }

    @ViewBuilder
    func rowsList(_ rows: [QuestionsTabRow]) -> some View {
        if !rows.isEmpty {
            LazyVStack(spacing: PaeoniaSpacing.space12) {
                ForEach(rows) { todayRow($0) }
            }
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: rows.map(\.id))
        }
    }
}
