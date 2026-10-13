import SwiftUI

/// The two choices every couple makes for their games: how they score, and the
/// language of the words. Setup and the settings sheet share it.
struct GameSettingsOptions: View {
    @Binding var playStyle: GamePlayStyle
    @Binding var language: GameLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
            playStyleSection
            languageSection
        }
    }

    private var playStyleSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.gamesSetupPlayStyleTitle)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(GamePlayStyle.allCases, id: \.self) { style in
                GameOptionRow(
                    title: style.title,
                    detail: style.detail,
                    isSelected: playStyle == style
                ) {
                    playStyle = style
                }
                .accessibilityIdentifier("games.playStyle.\(style.rawValue)")
            }
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(.gamesSetupLanguageTitle)
                    .font(PaeoniaTypography.sectionTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(.gamesSetupLanguageSubtitle)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }

            ForEach(GameLanguage.allCases, id: \.self) { option in
                GameOptionRow(title: option.title, detail: nil, isSelected: language == option) {
                    language = option
                }
                .accessibilityIdentifier("games.language.\(option.rawValue)")
            }
        }
    }
}

/// One choice in a list of choices. The selected one has an accent ring.
struct GameOptionRow: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaeoniaSpacing.space12) {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    Text(title)
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)
                    if let detail {
                        Text(detail)
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .paeoniaAccentPrimary : .paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }
            .padding(PaeoniaSpacing.cardContentPadding)
            .frame(minHeight: PaeoniaSpacing.buttonHeight)
            .background(isSelected ? .paeoniaSurfacePrimary : .paeoniaSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                    .strokeBorder(
                        isSelected ? .paeoniaAccentPrimary : .paeoniaSurfacePressed,
                        lineWidth: isSelected ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeHairline
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(PaeoniaMotion.stateChange, value: isSelected)
    }
}

extension GamePlayStyle {
    var title: LocalizedStringResource {
        switch self {
        case .against: .gamesPlayStyleAgainstTitle
        case .together: .gamesPlayStyleTogetherTitle
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .against: .gamesPlayStyleAgainstDetail
        case .together: .gamesPlayStyleTogetherDetail
        }
    }
}

extension GameLanguage {
    /// Each language in its own name, so a couple can read both.
    var title: LocalizedStringResource {
        switch self {
        case .en: .gamesLanguageEnglish
        case .nb: .gamesLanguageNorwegian
        }
    }

    /// The guesser's "The word is in English" line.
    var guessNoticeTitle: LocalizedStringResource {
        switch self {
        case .en: .gamesDrawAndGuessGuessWordLanguageEnglish
        case .nb: .gamesDrawAndGuessGuessWordLanguageNorwegian
        }
    }
}
