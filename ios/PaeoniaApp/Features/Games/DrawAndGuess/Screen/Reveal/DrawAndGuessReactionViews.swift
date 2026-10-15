import SwiftUI

extension DrawAndGuessReaction {
    var symbol: String {
        switch self {
        case .love: "heart.fill"
        case .laugh: "face.smiling"
        case .wow: "hands.clap.fill"
        }
    }

    /// The name on the guesser's button.
    var title: LocalizedStringResource {
        switch self {
        case .love: .gamesDrawAndGuessReactionLove
        case .laugh: .gamesDrawAndGuessReactionLaugh
        case .wow: .gamesDrawAndGuessReactionWow
        }
    }

    /// What the drawer reads: "Robin loved it" next to the drawing, or "Robin
    /// loved the UMBRELLA drawing" away from it, where "it" would say nothing.
    func drawerLine(partnerName: String, word: String? = nil) -> LocalizedStringResource {
        if let word {
            let shown = DrawAndGuessAnswer.display(word).uppercased()
            return switch self {
            case .love: .gamesDrawAndGuessWaitReactionLove(partnerName, shown)
            case .laugh: .gamesDrawAndGuessWaitReactionLaugh(partnerName, shown)
            case .wow: .gamesDrawAndGuessWaitReactionWow(partnerName, shown)
            }
        }
        return switch self {
        case .love: .gamesDrawAndGuessResultReactionLove(partnerName)
        case .laugh: .gamesDrawAndGuessResultReactionLaugh(partnerName)
        case .wow: .gamesDrawAndGuessResultReactionWow(partnerName)
        }
    }
}

/// "Tell [Name] what you think" with a love, a laugh and a wow button on the
/// guesser's result. Tapping one picks it. Tapping it again clears it.
struct DrawAndGuessReactionRow: View {
    let viewModel: DrawAndGuessViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var selected: DrawAndGuessReaction? { viewModel.reveal?.reaction }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(.gamesDrawAndGuessReactionPrompt(viewModel.partnerName))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space8))
                : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space12))
            layout {
                ForEach(DrawAndGuessReaction.allCases, id: \.self) { reaction in
                    button(reaction)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("draw.reaction")
    }

    private func button(_ reaction: DrawAndGuessReaction) -> some View {
        let isSelected = selected == reaction
        return Button {
            PaeoniaHaptics.selection()
            GameSound.tap.play(volume: 0.7)
            Task { await viewModel.react(reaction) }
        } label: {
            VStack(spacing: PaeoniaSpacing.space4) {
                Image(systemName: reaction.symbol)
                    .font(.title2)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .symbolEffect(.bounce, value: reduceMotion ? false : isSelected)
                    .accessibilityHidden(true)
                Text(reaction.title)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextPrimary)
            }
            .frame(minHeight: 64)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 96)
            .background(isSelected ? .paeoniaSurfacePrimary : .paeoniaSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                    .strokeBorder(
                        isSelected ? .paeoniaAccentPrimary : .clear,
                        lineWidth: PaeoniaRadius.strokeEmphasis
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(PaeoniaMotion.buttonPress, value: isSelected)
        .accessibilityLabel(Text(reaction.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("draw.reaction.\(reaction.rawValue)")
    }
}

/// What the drawer sees when the guesser reacted: the symbol and a short line.
/// The result screen animates it in and fires the haptic.
struct DrawAndGuessReactionCapsule: View {
    let reaction: DrawAndGuessReaction
    let partnerName: String
    /// Set where the drawing is not on screen, so the line names it.
    var word: String?

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: reaction.symbol)
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
            Text(reaction.drawerLine(partnerName: partnerName, word: word))
                .foregroundStyle(.paeoniaTextPrimary)
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("draw.result.reaction")
    }
}
