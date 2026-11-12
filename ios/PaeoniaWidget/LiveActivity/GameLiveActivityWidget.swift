#if WIDGET_EXTENSION
import ActivityKit
import SwiftUI
import WidgetKit

/// The partner's game on the Lock Screen and in the Dynamic Island. It names the partner and
/// the game and opens that game, and shows nothing of the game itself. The views are in
/// GameLiveActivityViews.swift.
struct GameLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GameLiveActivityAttributes.self) { context in
            let content = GameLiveActivityContent(context)
            GameLiveActivityLockScreenView(content: content)
                .activityBackgroundTint(Color.paeoniaWidgetBackground)
                .activitySystemActionForegroundColor(Color.paeoniaWidgetTextPrimary)
                .widgetURL(content.url)
        } dynamicIsland: { context in
            Self.island(GameLiveActivityContent(context))
        }
    }

    private static func island(_ content: GameLiveActivityContent) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                GameLiveActivityIcon(content: content, size: 44)
            }
            DynamicIslandExpandedRegion(.trailing) {
                GameLiveActivityJoinBadge(content: content)
            }
            DynamicIslandExpandedRegion(.bottom) {
                GameLiveActivityText(content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } compactLeading: {
            GameLiveActivityIcon(content: content, size: 24, speaksTitle: true)
        } compactTrailing: {
            GameLiveActivityCompactName(content: content)
        } minimal: {
            GameLiveActivityIcon(content: content, size: 24, speaksTitle: true)
        }
        .widgetURL(content.url)
        .keylineTint(Color.paeoniaWidgetAccentPrimary)
    }
}

private extension GameLiveActivityContent {
    init(_ context: ActivityViewContext<GameLiveActivityAttributes>) {
        self.init(attributes: context.attributes, state: context.state, isStale: context.isStale)
    }

    var url: URL? {
        LockScreenURL.game(path: game.path)
    }
}

private extension GameLiveActivityAttributes {
    static let preview = GameLiveActivityAttributes(activityID: "preview", partnerName: "Robin")
}

private extension GameLiveActivityAttributes.ContentState {
    static let mindMeld = Self(gameKind: .mindMeld, phase: .playing)
    static let drawAndGuess = Self(gameKind: .drawAndGuess, phase: .playing)
    static let ended = Self(gameKind: .mindMeld, phase: .ended)
}

#Preview("Lock Screen", as: .content, using: GameLiveActivityAttributes.preview) {
    GameLiveActivityWidget()
} contentStates: {
    GameLiveActivityAttributes.ContentState.mindMeld
    GameLiveActivityAttributes.ContentState.drawAndGuess
    GameLiveActivityAttributes.ContentState.ended
}

#Preview("Dynamic Island compact", as: .dynamicIsland(.compact), using: GameLiveActivityAttributes.preview) {
    GameLiveActivityWidget()
} contentStates: {
    GameLiveActivityAttributes.ContentState.mindMeld
    GameLiveActivityAttributes.ContentState.ended
}

#Preview("Dynamic Island expanded", as: .dynamicIsland(.expanded), using: GameLiveActivityAttributes.preview) {
    GameLiveActivityWidget()
} contentStates: {
    GameLiveActivityAttributes.ContentState.mindMeld
    GameLiveActivityAttributes.ContentState.drawAndGuess
}

#Preview("Dynamic Island minimal", as: .dynamicIsland(.minimal), using: GameLiveActivityAttributes.preview) {
    GameLiveActivityWidget()
} contentStates: {
    GameLiveActivityAttributes.ContentState.mindMeld
}
#endif
