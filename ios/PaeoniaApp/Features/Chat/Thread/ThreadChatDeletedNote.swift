import SwiftUI

/// What stays in the chat where a message was before its sender took it back. It sits on the
/// sender's side as a quiet outline, with no text, photo, voice message or reactions.
struct ThreadChatDeletedNote: View {
    let isCurrentUser: Bool
    let partnerName: String
    let shape: UnevenRoundedRectangle

    var body: some View {
        Text(isCurrentUser ? .dailyChatDeletedYou : .dailyChatDeletedPartner(partnerName))
            .font(PaeoniaTypography.caption.italic())
            .foregroundStyle(.paeoniaTextTertiary)
            .padding(.horizontal, PaeoniaSpacing.space12 + 2)
            .padding(.vertical, PaeoniaSpacing.space8)
            .overlay { shape.strokeBorder(.paeoniaTextTertiary.opacity(0.4), lineWidth: 1) }
    }
}
