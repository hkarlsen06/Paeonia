import SwiftUI

/// The list of built games, one card each. The game the partner is in comes
/// first, then games waiting for this person, then catalog order. A wide iPad shows
/// two columns.
///
/// A move in a game can change that order while the game is open. The card the
/// game opened from then keeps its place on screen, so closing the game lands on it.
struct GamesHubView: View {
    let viewModel: GamesViewModel
    let isShowingGame: Bool
    let open: (GamesDestination) -> Void
    @State private var isChangingSettings = false
    @State private var isWideLayout = false
    @State private var cardFrames = CardFrames()
    @State private var viewportHeight: CGFloat = 0
    @State private var openedCard: (kind: GameKind, anchor: UnitPoint)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                    ForEach(viewModel.hubGames, id: \.kind) { game in
                        card(for: game)
                    }
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
                .padding(.bottom, PaeoniaSpacing.space32)
                .paeoniaReadableWidth(
                    isWideLayout ? PaeoniaSpacing.wideContentWidth : PaeoniaSpacing.readableContentWidth
                )
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in
                viewportHeight = height
            }
            .onChange(of: viewModel.hubGames.map(\.kind)) {
                guard isShowingGame, let openedCard else { return }
                proxy.scrollTo(openedCard.kind, anchor: openedCard.anchor)
            }
            .onChange(of: isShowingGame) { _, isShowingGame in
                guard !isShowingGame, let openedCard else { return }
                proxy.scrollTo(openedCard.kind, anchor: openedCard.anchor)
                self.openedCard = nil
            }
        }
        .paeoniaWideLayout($isWideLayout)
        .refreshable { await viewModel.refresh() }
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
                .analyticsScreen("games_settings")
        }
        .accessibilityIdentifier("games.hub")
    }

    @ViewBuilder
    private func card(for game: any GameHubModel) -> some View {
        let card = game.card(viewModel.cardContext(for: game.kind, isOnHub: true)) { destination in
            openedCard = (game.kind, cardFrames.anchor(for: game.kind, viewportHeight: viewportHeight))
            open(destination)
        }
        if let card {
            card.onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { frame in
                cardFrames.frames[game.kind] = frame
            }
        }
    }

    private var columns: [GridItem] {
        let column = GridItem(.flexible(), spacing: PaeoniaSpacing.sectionSpacing, alignment: .top)
        return isWideLayout ? [column, column] : [column]
    }
}

/// Where each card sits in the visible part of the list. It is a plain class so
/// scrolling does not redraw the hub.
@MainActor
private final class CardFrames {
    var frames: [GameKind: CGRect] = [:]

    /// The anchor that puts the card back at the same height on screen when
    /// `scrollTo` uses it, since the anchor marks the same point in the card and
    /// the viewport.
    func anchor(for kind: GameKind, viewportHeight: CGFloat) -> UnitPoint {
        guard let frame = frames[kind], viewportHeight > frame.height else { return .top }
        let y = frame.minY / (viewportHeight - frame.height)
        return UnitPoint(x: 0.5, y: min(max(y, 0), 1))
    }
}
