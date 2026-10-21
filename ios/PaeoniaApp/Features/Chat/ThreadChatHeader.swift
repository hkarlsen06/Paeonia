import SwiftUI

/// The card that opens a memory's or a story's chat, so the conversation has something to
/// be about. A question's chat opens with its own question row instead.
nonisolated struct ThreadChatHeader: Hashable, Sendable {
    /// What this is, such as "Memory" or "Robin's story".
    let eyebrow: String
    /// The memory's title or the story's caption. Empty when there is none.
    let title: String
    /// A date line.
    let detail: String?
    /// The photo to show: the memory's first photo or the story's photo.
    let photoAssetID: UUID?
}

/// The header as a small card. It sits in the chat list like the question does in a question's
/// chat, so it scrolls away with the conversation.
struct ThreadChatHeaderCard: View {
    let header: ThreadChatHeader

    private static let photoSize: CGFloat = 64
    private static let maximumWidth: CGFloat = 360

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            if header.photoAssetID != nil {
                MemoryMediaImageView(
                    mediaAssetID: header.photoAssetID,
                    height: Self.photoSize,
                    cornerRadius: PaeoniaRadius.radius12,
                    allowsViewing: false
                )
                .frame(width: Self.photoSize)
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(verbatim: header.eyebrow)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                if !header.title.isEmpty {
                    Text(verbatim: header.title)
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .lineLimit(2)
                }
                if let detail = header.detail {
                    Text(verbatim: detail)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(PaeoniaSpacing.space12)
        .frame(maxWidth: Self.maximumWidth)
        .background(
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                .fill(.paeoniaSurfaceSecondary)
        )
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
