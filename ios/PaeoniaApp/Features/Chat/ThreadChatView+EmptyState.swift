import SwiftUI

extension ThreadChatView {
    @ViewBuilder
    var gameChatEmptyState: some View {
        if viewModel.subject.kind == .game, !viewModel.isLoading,
           viewModel.messages.isEmpty, viewModel.gameReferences.isEmpty,
           !viewModel.presence.partnerIsTyping {
            ViewThatFits(in: .vertical) {
                emptyGameChat
                ScrollView {
                    emptyGameChat
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, composerHeight)
        }
    }

    private var emptyGameChat: some View {
        PaeoniaEmptyStateView(
            title: .gamesConversationEmptyTitle,
            message: .gamesConversationEmptyMessage,
            systemImage: "bubble.left.and.bubble.right"
        )
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .accessibilityIdentifier("game.conversation.empty")
    }
}
