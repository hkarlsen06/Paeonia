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
        .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        .frame(maxWidth: .infinity)
    }

    /// The open result grows down from the pill, at least wide enough for a game's
    /// labels to fit, and narrower than the screen so it stays easy to scroll past.
    private var expanded: some View {
        PillWidthStack(minimumWidth: 300) {
            toggle
            VStack(spacing: PaeoniaSpacing.space8) {
                GameConversationHeader(
                    result: card.result, participants: participants,
                    loadState: card.loadState, onRetry: onRetry)
                Button(action: onReply) {
                    Label(.dailyChatActionReply, systemImage: "arrowshape.turn.up.left")
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
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
        GameChatResultLine(isExpanded: card.isExpanded, isFilled: !card.isExpanded) {
            Text(.gamesConversationResultTitle)
        } time: {
            Text(card.reference.finishedAt, format: .dateTime.hour().minute())
        }
    }
}

/// The quiet line a finished game, or a run of them, shows among the messages.
struct GameChatResultLine<Title: View, Time: View>: View {
    let isExpanded: Bool
    /// False when the line heads an open result, whose card draws the background.
    let isFilled: Bool
    @ViewBuilder let title: Title
    @ViewBuilder let time: Time

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: "flag.checkered")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
            title
                .foregroundStyle(.paeoniaTextPrimary)
            time
                .foregroundStyle(.paeoniaTextSecondary)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .imageScale(.small)
                .foregroundStyle(.paeoniaTextSecondary)
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space4)
        .background {
            if isFilled { Capsule().fill(.paeoniaSurfaceSecondary) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Stacks its views at the first view's own width, or `minimumWidth` if that is
/// wider, but never wider than offered. The rest fill that width and wrap to it.
private struct PillWidthStack: Layout {
    let minimumWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(of: subviews, offered: proposal.width)
        let height = subviews.reduce(0) { $0 + $1.sizeThatFits(.init(width: width, height: nil)).height }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = width(of: subviews, offered: bounds.width)
        var y = bounds.minY
        for subview in subviews {
            let size = ProposedViewSize(width: width, height: nil)
            subview.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top, proposal: size)
            y += subview.sizeThatFits(size).height
        }
    }

    private func width(of subviews: Subviews, offered: CGFloat?) -> CGFloat {
        let pill = subviews.first?.sizeThatFits(.unspecified).width ?? 0
        return min(max(pill, minimumWidth), offered ?? .infinity)
    }
}
