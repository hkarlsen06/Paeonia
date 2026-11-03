import SwiftUI

extension DailyChallengeScreen {
    var tabContent: QuestionsTabContent {
        let current = viewModel.snapshot.questions.filter {
            $0.hasOwnAnswer || viewModel.isSending($0.id) || $0.isAwaitingCurrentUserAnswer
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
