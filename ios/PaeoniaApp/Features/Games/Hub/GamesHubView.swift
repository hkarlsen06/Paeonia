import SwiftUI

/// The list of built games, one card each. The game the partner is in comes
/// first, then games waiting for this person, then catalog order.
struct GamesHubView: View {
    let viewModel: GamesViewModel
    let open: (GamesDestination) -> Void
    @State private var isChangingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                ForEach(viewModel.hubGames, id: \.kind) { game in
                    game.card(viewModel.cardContext(for: game.kind, isOnHub: true), open: open)
                }
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
            .paeoniaReadableWidth()
        }
        .refreshable { await viewModel.refresh() }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.mainTabGames))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isChangingSettings = true
                } label: {
                    Label {
                        Text(.gamesSettingsTitle)
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                .accessibilityIdentifier("games.hub.settings")
            }
        }
        .sheet(isPresented: $isChangingSettings) {
            GamesSettingsSheet(viewModel: viewModel)
        }
        .accessibilityIdentifier("games.hub")
    }
}
