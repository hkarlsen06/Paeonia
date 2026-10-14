import SwiftUI

/// The game screen with its "Our creatures" button.
///
/// `ExquisiteCorpseScreen` takes the button's action as a closure, and a closure
/// can't push onto the Games tab's path the way Draw & Guess's `NavigationLink`
/// does. This pushes the history from the screen's own stack entry instead.
struct ExquisiteCorpseScreenHost: View {
    let game: ExquisiteCorpseViewModel
    let history: ExquisiteCorpseHistoryViewModel
    @State private var showsHistory = false

    var body: some View {
        ExquisiteCorpseScreen(viewModel: game, openHistory: { showsHistory = true })
            .navigationDestination(isPresented: $showsHistory) {
                ExquisiteCorpseHistoryScreen(viewModel: history)
            }
    }
}
