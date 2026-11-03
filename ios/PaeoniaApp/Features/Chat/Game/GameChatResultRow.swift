import SwiftUI

/// A finished game and its optional details share one compact card.
struct GameChatResultRow: View {
    let card: GameChatResultCard
    let participants: DailyChallengeParticipants
    let onToggle: () -> Void
    let onReply: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            HStack(spacing: PaeoniaSpacing.space4) {
                Button(action: onToggle) { summary }
                .buttonStyle(.plain)
                .accessibilityValue(
                    Text(card.isExpanded ? .gamesConversationResultExpanded : .gamesConversationResultCollapsed)
                )
                .accessibilityIdentifier(
                    "game.conversation.result.\(card.reference.id.uuidString.lowercased())")
                if card.isExpanded {
                    Button(action: onReply) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityLabel(Text(.dailyChatActionReply))
                    .accessibilityIdentifier("game.conversation.result.reply")
                }
            }
            if card.isExpanded {
                GameConversationHeader(
                    result: card.result, participants: participants,
                    loadState: card.loadState, onRetry: onRetry)
            }
        }
        .padding(PaeoniaSpacing.space12)
        .background(.paeoniaSurfaceSecondary, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        .frame(maxWidth: .infinity)
    }

    private var summary: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: "flag.checkered")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(.gamesConversationResultTitle)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(
                    card.reference.finishedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute()
                )
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            }
            Spacer()
            Image(systemName: card.isExpanded ? "chevron.up" : "chevron.down")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
