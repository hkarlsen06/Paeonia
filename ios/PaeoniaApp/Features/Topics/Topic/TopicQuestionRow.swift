import SwiftUI

/// One question on a topic's screen: its short prompt and one line about where it
/// stands. The answers live on the question's own page, like the daily questions.
struct TopicQuestionRow: View {
    let item: TopicQuestionItem
    let state: TopicQuestionState
    let partnerName: String
    let partnerPhotoAssetID: UUID?
    var chatPreview: String?
    /// Something from the partner the user hasn't seen: their answer or a message.
    var isNew = false
    var isSending = false
    var onBringBack: (() -> Void)?

    private static let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)

    private var question: DailyChallengeQuestion {
        item.question
    }

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            leading

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(title)
                    .font(PaeoniaTypography.body.weight(state == .forYou || isNew ? .semibold : .regular))
                    .foregroundStyle(state == .skipped ? .paeoniaTextTertiary : .paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: PaeoniaSpacing.space8)

            trailing
        }
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.paeoniaSurfaceSecondary, in: Self.shape)
        .contentShape(Self.shape)
    }

    /// A partner question reads like the daily locked rows: who answered what.
    private var title: AttributedString {
        if state == .forYou {
            return AttributedString(localized: .dailyChallengeLockedRow(partnerName, question.shortPrompt))
        }
        return AttributedString(question.shortPrompt)
    }

    private var detail: String? {
        guard state == .together else { return nil }
        return chatPreview
    }

    @ViewBuilder
    private var leading: some View {
        if state == .forYou {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: partnerPhotoAssetID,
                name: partnerName,
                tint: .paeoniaPartnerTwo,
                size: 30
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.paeoniaTextInverse)
                    .frame(width: 15, height: 15)
                    .background(.paeoniaAccentPrimary, in: Circle())
                    .offset(x: 3, y: 3)
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let onBringBack {
            Button(action: onBringBack) {
                Text(.topicsRowBringBack)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .padding(.horizontal, PaeoniaSpacing.space12)
                    .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            }
            .buttonStyle(.plain)
        } else if isSending {
            ProgressView()
                .controlSize(.small)
                .tint(.paeoniaTextTertiary)
        } else if isNew {
            Circle()
                .fill(.paeoniaAccentPrimary)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
        } else if state != .skipped {
            Image(systemName: "chevron.right")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        }
    }
}
