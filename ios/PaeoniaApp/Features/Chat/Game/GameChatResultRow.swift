import SwiftUI

/// A finished game among the messages: one quiet line that opens into the full result.
struct GameChatResultRow: View {
    let card: GameChatResultCard
    let participants: DailyChallengeParticipants
    let onToggle: () -> Void
    let onReply: () -> Void
    let onRetry: () -> Void

    var body: some View {
        Group {
            if card.isExpanded {
                expanded
            } else {
                toggle
            }
        }
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space4)
        .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        .frame(maxWidth: .infinity)
    }

    private var expanded: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            HStack(spacing: PaeoniaSpacing.space4) {
                toggle
                Button(action: onReply) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityLabel(Text(.dailyChatActionReply))
                .accessibilityIdentifier("game.conversation.result.reply")
            }
            GameConversationHeader(
                result: card.result, participants: participants,
                loadState: card.loadState, onRetry: onRetry)
        }
        .padding(PaeoniaSpacing.space12)
        .background(.paeoniaSurfaceSecondary, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
    }

    private var toggle: some View {
        Button(action: onToggle) { line }
            .buttonStyle(.plain)
            .accessibilityValue(
                Text(card.isExpanded ? .gamesConversationResultExpanded : .gamesConversationResultCollapsed)
            )
            .accessibilityIdentifier("game.conversation.result.\(card.reference.id.uuidString.lowercased())")
    }

    /// The day divider above already names the day, so the line shows only the time.
    private var line: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: "flag.checkered")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
            Text(.gamesConversationResultTitle)
                .foregroundStyle(.paeoniaTextPrimary)
            Text(card.reference.finishedAt, format: .dateTime.hour().minute())
                .foregroundStyle(.paeoniaTextSecondary)
            Image(systemName: card.isExpanded ? "chevron.up" : "chevron.down")
                .imageScale(.small)
                .foregroundStyle(.paeoniaTextSecondary)
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space4)
        .background {
            if !card.isExpanded { Capsule().fill(.paeoniaSurfaceSecondary) }
        }
        .frame(maxWidth: card.isExpanded ? .infinity : nil, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
