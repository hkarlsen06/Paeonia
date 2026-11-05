import AppIntents
import SwiftUI

extension View {
    func chatConversationOnScreenForSiri(_ subject: ThreadChatSubject) -> some View {
        userActivity("no.paeonia.app.conversation") { activity in
            activity.appEntityIdentifier = EntityIdentifier(for: ChatConversationEntity.self, identifier: subject.id)
        }
    }

    func chatDraftFromSiri(viewModel: ThreadChatViewModel, text: Binding<String>) -> some View {
        task(id: SiriAppContext.shared.messageDraft?.body) {
            let context = SiriAppContext.shared
            if let draft = context.messageDraft,
                draft.ownerUserID == viewModel.participants.currentUserID,
                draft.subject == viewModel.subject
            {
                text.wrappedValue = draft.body
                context.messageDraft = nil
            }
        }
    }
}
