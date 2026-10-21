import SwiftUI

/// Search over the couple's content: the sheet, and where each kind of match opens.
extension MainTabView {
    /// The Search sheet. It clears its copy of the phone's content when it closes.
    func presentingSearch(on content: some View) -> some View {
        content.sheet(isPresented: $isSearchPresented, onDismiss: { models.search.end() }) {
            SearchScreen(
                viewModel: models.search,
                people: storyPeople,
                stories: storiesViewModel,
                loadContent: { await localSearchContent() },
                onSelect: openSearchResult,
                onClose: { isSearchPresented = false }
            )
            .analyticsScreen("search")
            .presentationDetents([.large])
            .environment(bannerCenter)
            .paeoniaTopBanner(bannerCenter)
        }
    }

    func openSearch() {
        isSearchPresented = true
        let search = models.search
        Task { await search.begin(loadContent: { await localSearchContent() }) }
    }

    /// Memories and stories as the phone holds them. Memories are read from the store, because the
    /// Memories tab loads its list only when it is first opened.
    private func localSearchContent() async -> SearchLocalContent {
        guard let userID = identity.currentUserID else { return SearchLocalContent() }
        let records = (try? await memoriesViewModel.memoryService.loadCachedMemories(
            ownerUserID: userID,
            includeHidden: false
        )) ?? []
        return SearchLocalContent(
            memories: MemoryTimeline.grouped(records).flatMap(\.memories),
            stories: storiesViewModel.stories
        )
    }

    /// Closes the sheet and opens the match. The sheet opens a story itself, over the results.
    private func openSearchResult(_ destination: SearchDestination) {
        isSearchPresented = false
        switch destination {
        case let .memory(id):
            selection.wrappedValue = .memories
            memoriesPath = [id]
        case let .question(id):
            startOpeningDailyChat(questionID: id)
        case let .storyChain(id):
            Task { await openStoryChainStory(id) }
        case .story, .widgetDrawing:
            break
        case let .drawAndGuessRound(id):
            Task { await openGameScreen(.drawAndGuessHistoryDetail(id)) }
        case let .exquisiteCorpseFigure(id):
            Task { await openGameScreen(.exquisiteCorpseHistoryDetail(id)) }
        }
    }

    private func openStoryChainStory(_ id: UUID) async {
        await openGameScreen(.storyChainHistoryDetail(id))
    }

    private func openGameScreen(_ destination: GamesDestination) async {
        selection.wrappedValue = .games
        gamesViewModel.configure(participants: gamesParticipants)
        await gamesViewModel.load()
        gamesViewModel.open(destination)
    }
}

extension View {
    /// A magnifying glass in the navigation bar that opens Search. Every tab's first screen has one.
    func searchToolbarButton(
        placement: ToolbarItemPlacement = .topBarLeading,
        action: @escaping () -> Void
    ) -> some View {
        toolbar {
            ToolbarItem(placement: placement) {
                Button(action: action) {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(Text(.searchTitle))
            }
        }
    }
}
