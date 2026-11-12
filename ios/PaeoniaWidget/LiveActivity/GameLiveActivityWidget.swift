#if WIDGET_EXTENSION
import ActivityKit
import SwiftUI
import WidgetKit

/// The partner's game on the Lock Screen and in the Dynamic Island. It names the partner, the game
/// and whose turn it is, opens that game, and shows nothing of the game itself. The views are in
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

    /// The expanded island cuts off what sits in its rounded corners, so its parts stay this far
    /// from the sides, and the text farther from the bottom.
    private static let islandSideInset: CGFloat = 8
    private static let islandBottomInset: CGFloat = 12

    private static func island(_ content: GameLiveActivityContent) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                GameLiveActivityIcon(content: content, size: 44)
                    .padding(.leading, islandSideInset)
            }
            DynamicIslandExpandedRegion(.trailing) {
                GameLiveActivityBadge(content: content)
                    .padding(.trailing, islandSideInset)
            }
            DynamicIslandExpandedRegion(.bottom) {
                GameLiveActivityText(content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, islandSideInset)
                    .padding(.bottom, islandBottomInset)
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
    static let mindMeld = Self(gameKind: .mindMeld, phase: .playing, turn: .none)
    static let yourTurn = Self(gameKind: .connectFour, phase: .playing, turn: .yours)
    static let theirTurn = Self(gameKind: .storyChain, phase: .playing, turn: .theirs)
    static let ended = Self(gameKind: .mindMeld, phase: .ended, turn: .none)
}

#Preview("Lock Screen", as: .content, using: GameLiveActivityAttributes.preview) {
    GameLiveActivityWidget()
} contentStates: {
    GameLiveActivityAttributes.ContentState.mindMeld
    GameLiveActivityAttributes.ContentState.yourTurn
    GameLiveActivityAttributes.ContentState.theirTurn
    GameLiveActivityAttributes.ContentState.ended
}

#Preview("Dynamic Island compact", as: .dynamicIsland(.compact), using: GameLiveActivityAttributes.preview) {
    GameLiveActivityWidget()
} contentStates: {
    GameLiveActivityAttributes.ContentState.mindMeld
    GameLiveActivityAttributes.ContentState.yourTurn
    GameLiveActivityAttributes.ContentState.ended
}

#Preview("Dynamic Island expanded", as: .dynamicIsland(.expanded), using: GameLiveActivityAttributes.preview) {
    GameLiveActivityWidget()
} contentStates: {
    GameLiveActivityAttributes.ContentState.mindMeld
    GameLiveActivityAttributes.ContentState.yourTurn
    GameLiveActivityAttributes.ContentState.theirTurn
}

#Preview("Dynamic Island minimal", as: .dynamicIsland(.minimal), using: GameLiveActivityAttributes.preview) {
    GameLiveActivityWidget()
} contentStates: {
    GameLiveActivityAttributes.ContentState.mindMeld
}
#endif
