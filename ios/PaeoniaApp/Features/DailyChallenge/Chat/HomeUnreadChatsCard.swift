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
/// there are none. Each row opens its chat.
struct HomeUnreadChatsCard: View {
    let chats: [UnreadChatRow]
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    var onOpenChat: (UUID) -> Void = { _ in }

    private static let maximumRows = 3

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                HStack {
                    PaeoniaCardEyebrow(.homeUnreadChatsEyebrow)
                    Spacer(minLength: PaeoniaSpacing.space12)
                    Text(chats.count, format: .number)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextInverse)
                        .padding(.horizontal, PaeoniaSpacing.space8)
                        .padding(.vertical, PaeoniaSpacing.space2)
                        .background(.paeoniaAccentPrimary, in: Capsule())
                        .accessibilityHidden(true)
                }

                ForEach(chats.prefix(Self.maximumRows)) { chat in
                    Button {
                        onOpenChat(chat.id)
                    } label: {
                        row(chat)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ chat: UnreadChatRow) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: partnerProfilePhotoAssetID,
                name: partnerName,
                tint: .paeoniaPartnerTwo,
                size: 40
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                if let prompt = chat.prompt {
                    Text(verbatim: prompt)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .lineLimit(1)
                }
                Text(.dailyChatCardUnreadTitle(partnerName))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                previewText(chat)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Circle()
                .fill(.paeoniaAccentPrimary)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func previewText(_ chat: UnreadChatRow) -> Text {
        if let preview = chat.preview?.trimmedNonEmpty {
            Text(verbatim: preview)
        } else {
            Text(.homeUnreadChatsHiddenPreview)
        }
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
