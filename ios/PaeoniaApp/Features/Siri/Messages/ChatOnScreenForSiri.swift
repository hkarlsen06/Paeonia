import AppIntents
import SwiftUI

extension View {
    func chatConversationOnScreenForSiri(_ subject: ThreadChatSubject) -> some View {
        userActivity("no.paeonia.app.conversation") { activity in
            activity.appEntityIdentifier = EntityIdentifier(for: ChatConversationEntity.self, identifier: subject.id)
        }
    }

    func chatDraftFromSiri(viewModel: ThreadChatViewModel, text: Binding<String>) -> some View {
        task(id: [SiriAppContext.shared.messageDraft?.id, viewModel.editTarget?.id]) {
            applyChatDraftFromSiri(viewModel: viewModel, text: text)
        }
    }
}

@MainActor
private func applyChatDraftFromSiri(viewModel: ThreadChatViewModel, text: Binding<String>) {
    let context = SiriAppContext.shared
    guard viewModel.editTarget == nil,
        let draft = context.messageDraft,
        draft.ownerUserID == viewModel.participants.currentUserID,
        draft.subject == viewModel.subject
    else { return }
    text.wrappedValue = draft.appending(to: text.wrappedValue)
    context.messageDraft = nil
}
