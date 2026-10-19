import MapKit
import SwiftUI

/// "Our places": the couple's memories on a map, opened from the Memories toolbar.
/// Tapping a pin shows its card, and the cards swipe through every placed memory,
/// newest first. A cluster zooms in, or lists its memories when they share a spot.
/// While no memory has a place, a panel lists the memories with "Add place" buttons,
/// so the screen is never an empty map.
struct MemoriesMapScreen: View {
    let viewModel: MemoriesViewModel
    let currentUserID: UUID?
    /// Guess my spot's guessed rounds, shown as pins next to the memories. Nil leaves them out.
    let gameRounds: GuessMySpotHistoryViewModel?

    @State private var selectedID: UUID?
    @State private var isShowingAll = true
    @State private var fitRequest = 0
    @State private var homeRegion: MKCoordinateRegion?
    @State private var cluster: MemoriesMapCluster?
    @State private var isShowingUnplaced = false
    @State private var opened: MemoriesMapDestination?
    /// A memory or round picked in the cluster sheet, opened once the sheet is gone.
    @State private var memoryToOpen: UUID?
    @State private var screenHeight: CGFloat = 800

    /// `initialSelectedID` and `initialCluster` open the screen with a card or a cluster
    /// sheet showing, for developer scenarios and screenshots.
    init(
        viewModel: MemoriesViewModel,
        currentUserID: UUID?,
        gameRounds: GuessMySpotHistoryViewModel? = nil,
        initialSelectedID: UUID? = nil,
        initialCluster: [MemoryMapEntry]? = nil
    ) {
        self.viewModel = viewModel
        self.currentUserID = currentUserID
        self.gameRounds = gameRounds
        _selectedID = State(initialValue: initialSelectedID)
        _cluster = State(initialValue: initialCluster.map { MemoriesMapCluster(ids: $0.map(\.id)) })
        initialFocusIDs = initialCluster.map { Set($0.map(\.id)) }
    }

    /// The scenario's cluster, which the first fit frames so its pin is the one on screen.
    private let initialFocusIDs: Set<UUID>?

    private var content: MemoriesMapContent {
        viewModel.mapContent(rounds: gameRounds?.memoryMapEntries ?? [])
    }

    /// The "Add place" panel, while no memory has a place. Game rounds don't count, but a
    /// picked round pin swaps the panel for its card.
    private func showsEmptyPanel(_ content: MemoriesMapContent) -> Bool {
        content.placedMemories.isEmpty && selectedID == nil
    }

    var body: some View {
        let content = self.content
        GeometryReader { proxy in
            ZStack {
                MemoriesMapView(
                    entries: content.placed,
                    selectedID: $selectedID,
                    isShowingAll: $isShowingAll,
                    fitRequest: fitRequest,
                    emptyRegion: homeRegion,
                    overlayInsets: overlayInsets(content, safeArea: proxy.safeAreaInsets, height: proxy.size.height),
                    onOpenCluster: { cluster = MemoriesMapCluster(ids: $0.map(\.id)) },
                    initialFocusIDs: initialFocusIDs
                )
                .ignoresSafeArea()

                scrims(content)
            }
            .overlay(alignment: .top) { totals(content) }
            .overlay(alignment: .bottom) {
                bottomControls(content, maxPanelHeight: proxy.size.height * 0.5)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }
        .navigationTitle(Text(.memoriesMapTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Full screen: the carousel owns the bottom edge. The tabs come back on the way out.
        .toolbar(.hidden, for: .tabBar)
        .background(Color.paeoniaBackgroundSecondary.ignoresSafeArea())
        .animation(PaeoniaMotion.stateChange, value: selectedID == nil)
        .animation(PaeoniaMotion.stateChange, value: content.placed.isEmpty)
        .animation(PaeoniaMotion.stateChange, value: isShowingAll)
        .onChange(of: content.placed.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
            // A memory deleted, hidden or moved while its cluster's sheet is open leaves
            // the sheet. The sheet closes once none is left.
            if let cluster, !cluster.ids.contains(where: ids.contains) { self.cluster = nil }
        }
        .sheet(item: $cluster, onDismiss: openPickedMemory) { cluster in
            MemoriesMapClusterSheet(
                entries: content.placed.filter { cluster.ids.contains($0.id) },
                maxHeight: screenHeight * 0.6
            ) { id in
                memoryToOpen = id
                self.cluster = nil
            }
        }
        .sheet(isPresented: $isShowingUnplaced) {
            MemoriesUnplacedSheet(viewModel: viewModel)
        }
        .navigationDestination(item: $opened) { destination in
            switch destination {
            case let .memory(memoryID):
                MemoryDetailView(memoryID: memoryID, currentUserID: currentUserID, viewModel: viewModel)
                    .analyticsScreen("memory_detail")
            case let .guessMySpotRound(roundID):
                if let gameRounds, let round = gameRounds.rounds.first(where: { $0.id == roundID }) {
                    GuessMySpotRoundDetail(round: round, history: gameRounds, showsClose: false)
                        .analyticsScreen("guess_my_spot_round")
                }
            }
        }
        .task {
            // The rounds come from the game's cache first, then the server.
            await gameRounds?.load()
            // Read again: the rounds may have just arrived.
            guard self.content.placed.isEmpty else { return }
            homeRegion = await MemoriesMapRegion.home()
        }
        .task {
            await gameRounds?.follow()
        }
    }

    // MARK: - Overlays

    /// Room the map keeps clear for the title, the totals, and the bottom controls when
    /// it frames the pins.
    private func overlayInsets(_ content: MemoriesMapContent, safeArea: EdgeInsets, height: CGFloat) -> UIEdgeInsets {
        let bottom: CGFloat = if showsEmptyPanel(content) {
            height * 0.5
        } else if selectedID != nil {
            150
        } else if !content.unplaced.isEmpty {
            // The "not on the map" pill.
            52
        } else {
            0
        }
        return UIEdgeInsets(top: safeArea.top + 28, left: 0, bottom: safeArea.bottom + bottom, right: 0)
    }

    /// Plum fades at the top and bottom keep the title and controls readable, like the
    /// couple map's distance line.
    private func scrims(_ content: MemoriesMapContent) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.paeoniaBackgroundSecondary, .paeoniaBackgroundSecondary.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)
            Spacer(minLength: 0)
            // Only behind controls, so pins near the bottom edge stay bright.
            if !content.placed.isEmpty, selectedID != nil || !content.unplaced.isEmpty {
                LinearGradient(
                    colors: [.paeoniaBackgroundSecondary.opacity(0), .paeoniaBackgroundSecondary.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func totals(_ content: MemoriesMapContent) -> some View {
        let totals = content.totals
        if totals.isWorthShowing {
            Text(verbatim: [
                String(localized: totals.countries == 1
                    ? .memoriesMapTotalsCountriesOne
                    : .memoriesMapTotalsCountries(totals.countries.formatted())),
                String(localized: totals.cities == 1
                    ? .memoriesMapTotalsCitiesOne
                    : .memoriesMapTotalsCities(totals.cities.formatted())),
            ].joined(separator: " · "))
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaMemory)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .padding(.top, PaeoniaSpacing.space4)
        }
    }

    @ViewBuilder
    private func bottomControls(_ content: MemoriesMapContent, maxPanelHeight: CGFloat) -> some View {
        if showsEmptyPanel(content) {
            MemoriesMapEmptyPanel(viewModel: viewModel, records: content.unplaced, maxHeight: maxPanelHeight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            VStack(spacing: PaeoniaSpacing.space12) {
                HStack(alignment: .bottom) {
                    if !content.unplaced.isEmpty {
                        unplacedPill(count: content.unplaced.count)
                    }
                    Spacer(minLength: 0)
                    if !isShowingAll {
                        showAllButton
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)

                if selectedID != nil {
                    MemoriesMapCarousel(entries: content.placed, selectedID: $selectedID) { id in
                        open(id, in: content)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, PaeoniaSpacing.space8)
        }
    }

    private func unplacedPill(count: Int) -> some View {
        Button {
            isShowingUnplaced = true
        } label: {
            Text(count == 1 ? .memoriesMapUnplacedOne : .memoriesMapUnplaced(count.formatted()))
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .padding(.horizontal, PaeoniaSpacing.space12)
                .frame(minHeight: 36)
                .background(.paeoniaSurfaceSecondary, in: Capsule())
                .overlay(Capsule().stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
    }

    private var showAllButton: some View {
        Button {
            fitRequest += 1
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .background(.paeoniaSurfaceSecondary, in: Circle())
                .overlay(Circle().stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.memoriesMapShowAll))
    }

    private func openPickedMemory() {
        guard let memoryToOpen else { return }
        self.memoryToOpen = nil
        open(memoryToOpen, in: content)
    }

    /// A memory opens its detail, a round opens the game's round.
    private func open(_ id: UUID, in content: MemoriesMapContent) {
        let kind = content.placed.first { $0.id == id }?.kind ?? .memory
        opened = kind == .guessMySpotRound ? .guessMySpotRound(id) : .memory(id)
    }
}

/// What a card or a cluster row opens.
enum MemoriesMapDestination: Hashable {
    case memory(UUID)
    case guessMySpotRound(UUID)
}

/// The memories in a cluster that zooming can't separate. The sheet reads their
/// current state from the timeline, so a change while it is open shows up.
struct MemoriesMapCluster: Identifiable {
    let ids: [UUID]

    var id: [UUID] { ids }
}
