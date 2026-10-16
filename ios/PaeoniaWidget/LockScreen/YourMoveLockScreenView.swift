#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

struct YourMoveLockScreenView: View {
    let entry: LockScreenEntry

    /// Opens the waiting game. With no known game, the widget opens the app.
    private var url: URL? {
        LockScreenURL.game(path: entry.snapshot.flatMap { LockScreenYourMove($0.games).gamePath })
    }

    var body: some View {
        if let games = entry.snapshot?.games {
            let move = LockScreenYourMove(games)
            ZStack {
                AccessoryWidgetBackground()
                if move.isMyTurn {
                    VStack(spacing: 1) {
                        Image(systemName: "die.face.5.fill").font(.system(size: 20))
                        Text(.widgetLockScreenYourMoveName)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                    .widgetAccentable()
                } else {
                    Image(systemName: "die.face.5")
                        .font(.system(size: 22))
                        .opacity(0.4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let count = move.badgeCount {
                    Text(count.formatted())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 4)
                        .background(.primary.opacity(0.25), in: Capsule())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabel(for: move)))
            .widgetURL(url)
        } else {
            LockScreenUnavailableView(symbol: "die.face.5", title: .widgetLockScreenYourMoveName)
        }
    }

    private func accessibilityLabel(for move: LockScreenYourMove) -> LocalizedStringResource {
        move.isMyTurn ? .widgetLockScreenYourMoveAccessibility(move.turnCount) : .widgetLockScreenYourMoveNone
    }
}
#endif