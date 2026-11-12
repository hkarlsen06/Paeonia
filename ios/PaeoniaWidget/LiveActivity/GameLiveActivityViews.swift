#if WIDGET_EXTENSION || DEBUG
import SwiftUI

// The views of the partner's game activity. The widget places them in the Lock Screen and the
// Dynamic Island (GameLiveActivityWidget), and the Debug app lays them out on an ordinary screen
// in the `live-activity-views` scenario, because simulator screenshots do not draw the island.

/// What every presentation shows. An ended or stale activity no longer says the partner is there.
struct GameLiveActivityContent {
    let partnerName: String
    let game: GameLiveActivityAttributes.Game
    let isPlaying: Bool

    init(attributes: GameLiveActivityAttributes, state: GameLiveActivityAttributes.ContentState, isStale: Bool) {
        let name = attributes.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        partnerName = name.isEmpty ? String(localized: .widgetLiveActivityPartnerFallback) : name
        game = state.gameKind
        isPlaying = state.phase == .playing && !isStale
    }

    var title: LocalizedStringResource {
        let gameName = String(localized: game.name)
        return isPlaying
            ? .widgetLiveActivityPlaying(partnerName, gameName)
            : .widgetLiveActivityWasPlaying(partnerName, gameName)
    }

    var subtitle: LocalizedStringResource {
        isPlaying ? .widgetLiveActivityJoin : .widgetLiveActivityOpenToCheck
    }
}

extension GameLiveActivityAttributes.Game {
    var name: LocalizedStringResource {
        switch self {
        case .drawAndGuess: .widgetGameDrawAndGuess
        case .mindMeld: .widgetGameMindMeld
        case .piccante: .widgetGamePiccante
        }
    }

    var symbol: String {
        switch self {
        case .drawAndGuess: "pencil.and.scribble"
        case .mindMeld: "brain.head.profile"
        case .piccante: "gift.fill"
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

/// The trailing part of the expanded island. Nothing once the partner may have left.
struct GameLiveActivityJoinBadge: View {
    let content: GameLiveActivityContent

    var body: some View {
        if content.isPlaying {
            Text(.widgetLiveActivityJoinShort)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PaeoniaBrandColors.background)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PaeoniaBrandColors.accent, in: Capsule())
        }
    }
}

/// The trailing part of the compact island.
struct GameLiveActivityCompactName: View {
    let content: GameLiveActivityContent

    var body: some View {
        Text(content.partnerName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(PaeoniaBrandColors.accent.opacity(content.isPlaying ? 1 : 0.5))
            .lineLimit(1)
            .frame(maxWidth: 72)
            // The icon beside it already says the whole line.
            .accessibilityHidden(true)
    }
}

struct GameLiveActivityIcon: View {
    let content: GameLiveActivityContent
    let size: CGFloat
    /// In the compact and minimal island the icon is what VoiceOver finds, so it says who plays what.
    var speaksTitle = false

    var body: some View {
        Image(systemName: content.game.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(PaeoniaBrandColors.accent)
            .frame(width: size, height: size)
            .background(PaeoniaBrandColors.accent.opacity(0.18), in: Circle())
            .opacity(content.isPlaying ? 1 : 0.5)
            .accessibilityLabel(Text(content.title))
            .accessibilityHidden(!speaksTitle)
    }
}
#endif
