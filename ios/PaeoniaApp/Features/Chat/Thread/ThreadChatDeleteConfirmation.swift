import SwiftUI

/// Asks before the user takes back a message, since it disappears for both of them.
struct ThreadChatDeleteConfirmation: ViewModifier {
    @Bindable var viewModel: ThreadChatViewModel

    func body(content: Content) -> some View {
        content.confirmationDialog(
            Text(.dailyChatDeleteTitle),
            isPresented: Binding(
                get: { viewModel.deleteTarget != nil },
                set: { if !$0 { viewModel.cancelDelete() } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.deleteTarget
        ) { _ in
            Button(role: .destructive) {
                Task { await viewModel.confirmDelete() }
            } label: {
                Text(.dailyChatDeleteAction)
            }
        } message: { target in
            // A message that never left the phone is not on the partner's phone yet.
            Text(
                target.isUnsent
                    ? .dailyChatDeleteUnsentMessage(viewModel.participants.partnerName)
                    : .dailyChatDeleteMessage(viewModel.participants.partnerName)
            )
        }
    }
}

extension View {
    func dailyChatDeleteConfirmation(viewModel: ThreadChatViewModel) -> some View {
        modifier(ThreadChatDeleteConfirmation(viewModel: viewModel))
    }
}
