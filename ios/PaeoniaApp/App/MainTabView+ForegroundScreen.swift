import SwiftUI

/// What the person has in front of them, which the notification router reads to hold back a notice
/// about something already on screen.
extension MainTabView {
    var foregroundScreen: ForegroundScreen {
        if let visibleChatSubject { return .chat(visibleChatSubject) }
        if isAnswerFlowPresented {
            let today = dailyChallengeViewModel.snapshot.todayQuestion
            return .answering(instanceID: today?.id, coupleDayID: today?.coupleDayID)
        }
        if let partnerAnswerQuestion {
            return .answering(instanceID: partnerAnswerQuestion.id, coupleDayID: partnerAnswerQuestion.coupleDayID)
        }
        guard selection.wrappedValue == .questions, !isModalOpen, !widgetDrawingPresented.wrappedValue else {
            return .elsewhere
        }
        return questionsPath.isEmpty ? .questions : .topics
    }

    func tellingRouterTheScreen(on content: some View) -> some View {
        content
            .onChange(of: foregroundScreen, initial: true) { _, screen in
                PaeoniaNotificationRouter.shared.screen = screen
            }
            .onDisappear { PaeoniaNotificationRouter.shared.screen = .elsewhere }
    }
}
