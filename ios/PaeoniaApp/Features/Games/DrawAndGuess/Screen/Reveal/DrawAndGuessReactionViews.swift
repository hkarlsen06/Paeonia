import SwiftUI

/// "Tell [Name] what you think" over the emoji row, on the result of a finished round. Both
/// partners can react to the round, the guesser and the drawer, and what the partner chose shows
/// under the row.
struct DrawAndGuessReactionRow: View {
    let viewModel: DrawAndGuessViewModel

    var body: some View {
        if let round = viewModel.round {
            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.gamesDrawAndGuessReactionPrompt(viewModel.partnerName))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
                ReactionSection(target: .drawAndGuessRound(round.id), alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("draw.reaction")
        }
    }
}

/// What the drawer sees on the screen that waits for the partner's next word, when the partner
/// reacted to the round just drawn. The drawing is not on this screen, so the line names the word.
struct DrawAndGuessReactionCapsule: View {
    let emoji: String
    let partnerName: String
    /// Lowercase.
    let word: String?

    var body: some View {
        Text(line)
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("draw.result.reaction")
    }

    /// "Robin reacted ❤️ to the UMBRELLA drawing". The word goes in front of "drawing" ("PARAPLY-tegningen"
    /// in Norwegian), so plurals, any gender and custom phrases all read right.
    private var line: LocalizedStringResource {
        guard let word else { return .reactionsPartner(partnerName, emoji) }
        return .gamesDrawAndGuessWaitReaction(partnerName, emoji, DrawAndGuessAnswer.display(word).uppercased())
    }
}
