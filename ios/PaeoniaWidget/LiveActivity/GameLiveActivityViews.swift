#if WIDGET_EXTENSION || DEBUG
import SwiftUI

// The views of the partner's game activity. The widget places them in the Lock Screen and the
// Dynamic Island (GameLiveActivityWidget), and the Debug app lays them out on an ordinary screen
// in the `live-activity-views` scenario, because simulator screenshots do not draw the island.

/// What every presentation shows. An ended or stale activity no longer says the partner is there,
/// and no longer says whose turn it is.
struct GameLiveActivityContent {
    let partnerName: String
    let game: GameLiveActivityAttributes.Game
    let isPlaying: Bool
    /// Whose turn it is, or `none` once the activity ended or went stale.
    let turn: GameLiveActivityAttributes.Turn

    init(attributes: GameLiveActivityAttributes, state: GameLiveActivityAttributes.ContentState, isStale: Bool) {
        let name = attributes.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        partnerName = name.isEmpty ? String(localized: .widgetLiveActivityPartnerFallback) : name
        game = state.gameKind
        isPlaying = state.phase == .playing && !isStale
        turn = isPlaying ? state.turn : .none
    }

    var title: LocalizedStringResource {
        let gameName = String(localized: game.name)
        guard isPlaying else {
            return .widgetLiveActivityWasPlaying(partnerName, gameName)
        }
        switch turn {
        case .yours: return .widgetLiveActivityYourTurn
        case .theirs: return .widgetLiveActivityWaitingFor(partnerName)
        case .none: return .widgetLiveActivityPlaying(partnerName, gameName)
        }
    }

    var subtitle: LocalizedStringResource {
        guard isPlaying else {
            return .widgetLiveActivityOpenToCheck
        }
        switch turn {
        case .yours: return .widgetLiveActivityGameWith(String(localized: game.name), partnerName)
        case .theirs: return game.name
        case .none: return .widgetLiveActivityJoin
        }
    }

    /// The short label at the right of the expanded island, or nil for none.
    var badge: LocalizedStringResource? {
        guard isPlaying else {
            return nil
        }
        switch turn {
        case .yours: return .widgetLiveActivityPlayShort
        case .theirs: return nil
        case .none: return .widgetLiveActivityJoinShort
        }
    }

    /// The whole activity in one line, for VoiceOver where only the icon shows.
    var accessibilityLabel: String {
        "\(String(localized: title)), \(String(localized: subtitle))"
    }
}

extension GameLiveActivityAttributes.Game {
    var name: LocalizedStringResource {
        switch self {
        case .ludo: .widgetGameLudo
        case .drawAndGuess: .widgetGameDrawAndGuess
        case .connectFour: .widgetGameConnectFour
        case .mindMeld: .widgetGameMindMeld
        case .consensio: .widgetGameConsensio
        case .guessMySpot: .widgetGameGuessMySpot
        case .dotsAndBoxes: .widgetGameDotsAndBoxes
        case .ultimateTicTacToe: .widgetGameUltimateTicTacToe
        case .piccante: .widgetGamePiccante
        case .storyChain: .widgetGameStoryChain
        case .exquisiteCorpse: .widgetGameExquisiteCorpse
        }
    }

    var symbol: String {
        switch self {
        case .ludo: "die.face.5.fill"
        case .drawAndGuess: "pencil.and.scribble"
        case .connectFour: "circle.grid.3x3.fill"
        case .mindMeld: "brain.head.profile"
        case .consensio: "slider.horizontal.below.rectangle"
        case .guessMySpot: "mappin.and.ellipse"
        case .dotsAndBoxes: "square.grid.3x3"
        case .ultimateTicTacToe: "number"
        case .piccante: "gift.fill"
        case .storyChain: "book.pages.fill"
        case .exquisiteCorpse: "lizard.fill"
        }
    }
}

struct GameLiveActivityLockScreenView: View {
    let content: GameLiveActivityContent

    var body: some View {
        HStack(spacing: 12) {
            GameLiveActivityIcon(content: content, size: 44)
            GameLiveActivityText(content: content)
            Spacer(minLength: 0)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

struct GameLiveActivityText: View {
    let content: GameLiveActivityContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.title)
                .font(.headline)
                .foregroundStyle(PaeoniaBrandColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(content.subtitle)
                .font(.subheadline)
                .foregroundStyle(PaeoniaBrandColors.textSecondary)
                .lineLimit(2)
        }
    }
}

/// The trailing part of the expanded island. Nothing while the partner is on their turn, or once
/// they may have left.
struct GameLiveActivityBadge: View {
    let content: GameLiveActivityContent

    var body: some View {
        if let badge = content.badge {
            Text(badge)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PaeoniaBrandColors.background)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PaeoniaBrandColors.accent, in: Capsule())
        }
    }
}

/// The trailing part of the compact island: the partner's name, or "Your turn" when it is.
struct GameLiveActivityCompactName: View {
    let content: GameLiveActivityContent

    var body: some View {
        label
            .font(.caption2.weight(.semibold))
            .foregroundStyle(PaeoniaBrandColors.accent.opacity(content.isPlaying ? 1 : 0.5))
            .lineLimit(1)
            .frame(maxWidth: 72)
            // The icon beside it already says the whole line.
            .accessibilityHidden(true)
    }

    private var label: Text {
        content.turn == .yours ? Text(.widgetLiveActivityYourTurn) : Text(content.partnerName)
    }
}

struct GameLiveActivityIcon: View {
    let content: GameLiveActivityContent
    let size: CGFloat
    /// In the compact and minimal island the icon is what VoiceOver finds, so it says the whole activity.
    var speaksTitle = false

    var body: some View {
        Image(systemName: content.game.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(PaeoniaBrandColors.accent)
            .frame(width: size, height: size)
            .background(PaeoniaBrandColors.accent.opacity(0.18), in: Circle())
            .opacity(content.isPlaying ? 1 : 0.5)
            .accessibilityLabel(Text(verbatim: content.accessibilityLabel))
            .accessibilityHidden(!speaksTitle)
    }
}
#endif
