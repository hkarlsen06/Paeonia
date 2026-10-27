import SwiftUI

private struct SubjectConversationRequests: ViewModifier {
    @Binding var requestedID: UUID?
    let conversations: [SubjectConversation]
    let isOpening: Bool
    let open: (SubjectConversation) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: requestedID, initial: true) { openRequested() }
            .onChange(of: conversations) { openRequested() }
            .onChange(of: isOpening) { openRequested() }
    }

    private func openRequested() {
        guard !isOpening, let requestedID, let conversation = conversations.first(where: { $0.id == requestedID })
        else {
            return
        }
        self.requestedID = nil
        open(conversation)
    }
}

extension View {
    func requestedConversation(
        id: Binding<UUID?>, conversations: [SubjectConversation], isOpening: Bool,
        open: @escaping (SubjectConversation) -> Void
    ) -> some View {
        modifier(
            SubjectConversationRequests(requestedID: id, conversations: conversations, isOpening: isOpening, open: open)
        )
    }
}
