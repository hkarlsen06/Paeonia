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
            history: historyViewModel?.questions ?? [],
            conversations: ordinaryConversations,
            today: viewModel.snapshot.todayLocalDate,
            timeZone: viewModel.snapshot.timeZone,
            attentionDate: viewModel.attentionDate
        )
    }

    /// The daily prompt already offers today's answer action. Keep a separate row
    /// only when it opens an unread conversation from an earlier shared round.
    var attentionRows: [QuestionsTabRow] {
        tabContent.attention.filter { row in
            guard viewModel.homeCardState.kind != .complete,
                  case .question(let question) = row,
                  question.id == viewModel.snapshot.todayQuestion?.id else { return true }
            return viewModel.hasUnreadChat(for: question.questionID)
        }
    }

    @ViewBuilder
    func rowsList(_ rows: [QuestionsTabRow]) -> some View {
        if !rows.isEmpty {
            VStack(spacing: PaeoniaSpacing.space12) {
                ForEach(rows) { todayRow($0) }
            }
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: rows.map(\.id))
        }
    }
}
