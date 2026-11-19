import SwiftUI

/// One question chat with a partner message the user has not opened yet.
struct UnreadChatRow: Identifiable, Equatable {
    /// The question the chat is about. A couple has one chat per question.
    let id: UUID
    /// The question text, when today's questions include it.
    let prompt: String?
    let preview: String?
}

/// The Home card listing chats with new partner messages. Home hides it when
/// there are none. Each row is the partner's newest message in one chat, under
/// its question when today's questions include it, and opens that chat.
struct HomeUnreadChatsCard: View {
    let chats: [UnreadChatRow]
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    var onOpenChat: (UUID) -> Void = { _ in }

    private static let maximumRows = 3
    private static let avatarSize: CGFloat = 36
    private static let dotSize: CGFloat = 10

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        PaeoniaCard(padding: PaeoniaSpacing.space12) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                ForEach(chats.prefix(Self.maximumRows)) { chat in
                    Button {
                        onOpenChat(chat.id)
                    } label: {
                        row(chat)
                    }
                    .buttonStyle(.paeoniaPressableRow)
                }
            }
        }
    }

    private func row(_ chat: UnreadChatRow) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            PaeoniaCoupleAvatar(
                mediaAssetID: partnerProfilePhotoAssetID,
                name: partnerName,
                tint: .paeoniaPartnerTwo,
                size: Self.avatarSize,
                isCurrentUser: false
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(.paeoniaAccentPrimary)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .overlay(Circle().stroke(.paeoniaBackgroundPrimary, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                if let prompt = chat.prompt {
                    Text(verbatim: prompt)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .lineLimit(1)
                }
                previewText(chat)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                    // One line reads as a list. At accessibility sizes that is a word or two.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextTertiary)
        }
        .paeoniaTapTarget()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(chat))
    }

    private func previewText(_ chat: UnreadChatRow) -> Text {
        if let preview = chat.preview?.trimmedNonEmpty {
            Text(verbatim: preview)
        } else {
            Text(.homeUnreadChatsHiddenPreview)
        }
    }

    private func accessibilityLabel(_ chat: UnreadChatRow) -> Text {
        let parts = [
            String(localized: .dailyChatCardUnreadTitle(partnerName)),
            chat.preview?.trimmedNonEmpty ?? String(localized: .homeUnreadChatsHiddenPreview),
            chat.prompt,
        ]
        return Text(verbatim: parts.compactMap(\.self).joined(separator: ". "))
    }
}

#if DEBUG
#Preview {
    HomeUnreadChatsCard(
        chats: [
            UnreadChatRow(id: UUID(), prompt: "What made you smile today?", preview: "Haha the dog again 😂"),
            UnreadChatRow(id: UUID(), prompt: nil, preview: nil),
        ],
        partnerName: "Oda",
        partnerProfilePhotoAssetID: nil
    )
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
