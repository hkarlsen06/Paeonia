import SwiftUI

/// The result's contents load only after the person opens this card.
struct GameChatResultRow: View {
    let card: GameChatResultCard
    let participants: DailyChallengeParticipants
    let onToggle: () -> Void
    let onReply: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Button(action: onToggle) {
                summary
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                Text(card.isExpanded ? .gamesConversationResultExpanded : .gamesConversationResultCollapsed)
            )
            .accessibilityIdentifier(
                "game.conversation.result.\(card.reference.id.uuidString.lowercased())")
            if card.isExpanded {
                GameConversationHeader(
                    result: card.result, participants: participants,
                    loadState: card.loadState, onRetry: onRetry)
                Button(action: onReply) {
                    Label {
                        Text(.dailyChatActionReply)
                    } icon: {
                        Image(systemName: "arrowshape.turn.up.left")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityIdentifier("game.conversation.result.reply")
            }
        }
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
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(
                    card.reference.finishedAt, format: .dateTime.day().month(.abbreviated).hour().minute()
                )
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            }
            Spacer()
            Image(systemName: card.isExpanded ? "chevron.up" : "chevron.down")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
        }
        .padding(PaeoniaSpacing.space12)
        .background(
            .paeoniaSurfaceSecondary, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
    }
}
