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

    /// The open result keeps the pill's width, so it reads as the pill grown downward.
    private var expanded: some View {
        PillWidthStack {
            toggle
            VStack(spacing: PaeoniaSpacing.space8) {
                GameConversationHeader(
                    result: card.result, participants: participants,
                    loadState: card.loadState, onRetry: onRetry)
                Button(action: onReply) {
                    Label(.dailyChatActionReply, systemImage: "arrowshape.turn.up.left")
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityIdentifier("game.conversation.result.reply")
            }
            .padding([.horizontal, .bottom], PaeoniaSpacing.space12)
        }
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
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Stacks its views at the first view's own width, which the rest fill and wrap to.
private struct PillWidthStack: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(of: subviews)
        let height = subviews.reduce(0) { $0 + $1.sizeThatFits(.init(width: width, height: nil)).height }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = width(of: subviews)
        var y = bounds.minY
        for subview in subviews {
            let size = ProposedViewSize(width: width, height: nil)
            subview.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top, proposal: size)
            y += subview.sizeThatFits(size).height
        }
    }

    private func width(of subviews: Subviews) -> CGFloat {
        subviews.first?.sizeThatFits(.unspecified).width ?? 0
    }
}
