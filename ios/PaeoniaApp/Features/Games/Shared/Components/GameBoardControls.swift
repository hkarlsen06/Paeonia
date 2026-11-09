import SwiftUI

extension EnvironmentValues {
    /// False for a board drawn as a picture, such as a chat or hub thumbnail, which has nothing to control.
    @Entry var gameBoardShowsControls = true
}

/// A native, scrollable alternative to precise board gestures.
struct GameBoardControls<Controls: View>: View {
    @State private var isPresented = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @AccessibilityPresentation(.controls) private var showsControls
    @Environment(\.gameBoardShowsControls) private var isAvailable
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        Group {
            if isAvailable, showsControls || isPresented {
                Button { isPresented = true } label: {
                    Label(.gamesBoardControls, systemImage: "hand.tap")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("games.board.controls")
            }
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                Form { controls() }
                    .paeoniaGroupedList()
                    .navigationTitle(Text(.gamesBoardControls))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(.commonDone) { isPresented = false }
                                .accessibilityIdentifier("games.board.controls.close")
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .paeoniaBanner(bannerCenter)
        }
    }
}
