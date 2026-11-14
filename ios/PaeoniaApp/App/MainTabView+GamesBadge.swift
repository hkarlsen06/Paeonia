import SwiftUI

extension MainTabView {
    /// Seeing the Games hub clears its badge (`games:mark_waiting_games_seen`). The waiting
    /// games stay under "Right now".
    func clearingGamesBadge(on content: some View) -> some View {
        content.task(id: gamesHubShowsBadge) {
            guard gamesHubShowsBadge else { return }
            try? await PaeoniaConvexClientProvider.shared.client().mutation("games:mark_waiting_games_seen")
        }
    }

    /// The Games hub is on screen while its tab counts something new.
    private var gamesHubShowsBadge: Bool {
        scenePhase == .active && selection.wrappedValue == .games && gamesPath.isEmpty
            && AppBadges.shared.counts.games > 0
    }
}
