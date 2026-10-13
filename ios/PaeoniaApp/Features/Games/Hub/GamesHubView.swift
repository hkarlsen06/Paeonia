import SwiftUI

/// The list of games. Draw & Guess is the only one so far.
struct GamesHubView: View {
    let viewModel: GamesViewModel
    let open: (GamesDestination) -> Void
    @State private var isChangingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                if let summary = viewModel.hubSummary {
                    DrawAndGuessHubCard(
                        summary: summary,
                        partnerName: viewModel.partnerName,
                        me: viewModel.drawAndGuess.me,
                        partner: viewModel.drawAndGuess.partner,
                        open: { open(.drawAndGuess) },
                        openHistory: { open(.drawAndGuessHistory) }
                    )
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
