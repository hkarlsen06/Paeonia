import SwiftUI

/// The built games. "Right now" shows full cards for the games the partner is in, then
/// the games waiting for this person. Every other game is a small tile in a grid below,
/// in catalog order, so the whole catalog fits in about two screens. Without a game for
/// "Right now", the grid is all there is and has no heading. A wide iPad shows two
/// columns of full cards.
///
/// A move in a game can move its card between the two while the game is open. The card
/// the game opened from then keeps its place on screen, so closing the game lands on it.
///
/// A long press on a card or tile shows the items of the game's menu.
struct GamesHubView: View {
    let viewModel: GamesViewModel
    let isShowingGame: Bool
    let open: (GamesDestination) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var cardSpace
    @State private var isChangingSettings = false
    @State private var isWideLayout = false
    @State private var cardFrames = CardFrames()
    @State private var viewportHeight: CGFloat = 0
    @State private var openedCard: (kind: GameKind, anchor: UnitPoint)?
    @State private var markEditor: BoardMarkEditorModel?
    @State private var tutorial: GameTutorial?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                sections
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
            .onChange(of: viewModel.hubFeaturedGames.map(\.kind)) {
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
        .sheet(isPresented: isEditingMark) {
            if let markEditor {
                BoardMarkEditorView(color: .boardGameMine, model: markEditor)
                    .analyticsScreen("mark_editor")
            }
        }
        .sheet(isPresented: isShowingTutorial) {
            if let tutorial {
                GameTutorialSheet(tutorial: tutorial)
            }
        }
        .accessibilityIdentifier("games.hub")
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
            let featured = viewModel.hubFeaturedGames
            if !featured.isEmpty {
                section(.gamesHubSectionRightNow) {
                    featuredGrid(featured)
                }
            }
            section(featured.isEmpty ? nil : .gamesHubSectionMore) {
                LazyVGrid(columns: gridColumns, spacing: PaeoniaSpacing.space16) {
                    ForEach(viewModel.hubGridGames, id: \.kind) { game in
                        card(for: game, isCompact: true)
                    }
                }
            }
        }
        // A card moves between "Right now" and the grid when the partner comes or goes, a turn
        // changes, or "Not now" is tapped. These arrive in separate updates, so the animation
        // follows the cards that end up under "Right now" rather than any one of them.
        .animation(reduceMotion ? nil : PaeoniaMotion.cardReveal, value: viewModel.hubFeaturedGames.map(\.kind))
    }

    /// One card per row, two on a wide iPad. A `Grid` rather than a lazy grid, so the
    /// two cards in a row share the taller one's height.
    private func featuredGrid(_ featured: [any GameHubModel]) -> some View {
        let perRow = isWideLayout ? 2 : 1
        let spacing = PaeoniaSpacing.sectionSpacing
        return Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(Array(stride(from: 0, to: featured.count, by: perRow)), id: \.self) { start in
                GridRow(alignment: .top) {
                    ForEach(featured[start ..< min(start + perRow, featured.count)], id: \.kind) { game in
                        card(for: game)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func card(for game: any GameHubModel, isCompact: Bool = false) -> some View {
        let openFromCard = { (destination: GamesDestination) in
            openedCard = (game.kind, cardFrames.anchor(for: game.kind, viewportHeight: viewportHeight))
            open(destination)
        }
        if let card = game.card(viewModel.cardContext(for: game.kind, isOnHub: true), open: openFromCard) {
            card.environment(\.gameHubCardIsCompact, isCompact)
                .contentShape(
                    .contextMenuPreview,
                    RoundedRectangle(
                        cornerRadius: isCompact ? PaeoniaRadius.radius20 : PaeoniaRadius.radius28,
                        style: .continuous
                    )
                )
                .contextMenu { menuItems(for: game, open: openFromCard) }
                .id(game.kind)
                .matchedGeometryEffect(id: game.kind, in: cardSpace)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { frame in
                    cardFrames.frames[game.kind] = frame
                }
        }
    }

    /// The same items as the game's own menu. "Past games" opens like a tap on the card.
    private func menuItems(
        for game: any GameHubModel,
        open: @escaping (GamesDestination) -> Void
    ) -> some View {
        let history = game.historyLink
        var editMark: (() -> Void)?
        if game.hasBoardMark {
            editMark = { openMarkEditor() }
        }
        var showTutorial: (() -> Void)?
        if let tutorial = GameTutorial(kind: game.kind, partnerName: viewModel.partnerName) {
            showTutorial = { show(tutorial) }
        }
        return GameMenuItems(
            history: history,
            openHistory: {
                if let history { open(history.destination) }
            },
            editMark: editMark,
            showTutorial: showTutorial
        )
    }

    private func openMarkEditor() {
        Task { markEditor = await viewModel.makeMarkEditor() }
    }

    /// The game then skips showing the cards on its own when it first opens.
    private func show(_ tutorial: GameTutorial) {
        tutorial.hasBeenShown = true
        self.tutorial = tutorial
    }

    private var isEditingMark: Binding<Bool> {
        Binding(
            get: { markEditor != nil },
            set: { isPresented in
                if !isPresented {
                    markEditor = nil
                }
            }
        )
    }

    private var isShowingTutorial: Binding<Bool> {
        Binding(
            get: { tutorial != nil },
            set: { isPresented in
                if !isPresented {
                    tutorial = nil
                }
            }
        )
    }

    private func section(
        _ title: LocalizedStringResource?,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            if let title {
                Text(title)
                    .font(PaeoniaTypography.sectionTitle)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
    }

    /// Two tiles across on every iPhone, more on iPad. With the largest text sizes a tile
    /// takes the full width, so its name and status still fit.
    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), alignment: .top)]
        }
        return [GridItem(.adaptive(minimum: 150), spacing: PaeoniaSpacing.space16, alignment: .top)]
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
