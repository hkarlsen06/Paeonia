import SwiftUI

/// Search over what the couple shared. It opens as a sheet from Home and lists matches by kind.
/// A tap closes the sheet and opens the match, except a story, which opens over the sheet.
struct SearchScreen: View {
    @Bindable var viewModel: SearchViewModel
    let people: StoryPeople
    let stories: StoriesViewModel
    /// Reads the memories and stories the phone searches.
    let loadContent: @MainActor () async -> SearchLocalContent
    let onSelect: (SearchDestination) -> Void
    let onClose: () -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var expandedKinds = Set<SearchResultKind>()
    @State private var storyViewer: StoryViewerContent?
    /// The starred items, shown before anything is typed.
    @State private var starred = SavedFavoritesViewModel.live()
    @State private var drawingPreview: FavoriteSummary?

    /// How many matches of a kind show before "Show all".
    private static let collapsedCount = 5

    var body: some View {
        NavigationStack {
            List {
                if viewModel.phase == .idle {
                    starredSection
                }
                ForEach(viewModel.results.kinds) { kind in
                    section(of: kind)
                }
                if viewModel.phase == .finished, !viewModel.results.isEmpty, let problem = viewModel.onlineProblem {
                    onlineProblemSection(problem)
                }
            }
            .paeoniaGroupedList()
            .overlay { placeholder }
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(.searchPrompt)
            )
            .searchFocused($isSearchFocused)
            .navigationTitle(Text(.searchTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel, action: onClose) { Text(.commonClose) }
                }
            }
        }
        .presentationBackground(.paeoniaBackgroundPrimary)
        .fullScreenCover(item: $storyViewer) { content in
            StoryViewer(content: content, people: people, viewModel: stories)
                .analyticsScreen("story_viewer")
        }
        .sheet(item: $drawingPreview) { favorite in
            FavoriteDrawingPreview(favorite: favorite, people: people)
        }
        .task { isSearchFocused = true }
        .task(id: starred.refreshKey) { await starred.load() }
        .task { await viewModel.observeMemoryChanges(loadContent: loadContent) }
        .onChange(of: stories.stories) {
            Task { await viewModel.refreshContent(loadContent: loadContent) }
        }
    }

    // MARK: - Results

    private func section(of kind: SearchResultKind) -> some View {
        let all = viewModel.results.results(of: kind)
        let isExpanded = expandedKinds.contains(kind)
        let shown = isExpanded ? all : Array(all.prefix(Self.collapsedCount))
        return Section {
            ForEach(shown) { result in
                Button { select(result) } label: {
                    SearchResultRow(result: result, words: viewModel.words, people: people)
                }
                .listRowBackground(Color.paeoniaSurfacePrimary)
            }
            if all.count > Self.collapsedCount {
                Button {
                    withAnimation(PaeoniaMotion.stateChange) {
                        if isExpanded { expandedKinds.remove(kind) } else { expandedKinds.insert(kind) }
                    }
                } label: {
                    Text(toggleTitle(isExpanded: isExpanded, count: all.count))
                        .foregroundStyle(.paeoniaAccentPrimary)
                }
                .listRowBackground(Color.paeoniaSurfacePrimary)
            }
        } header: {
            Text(kind.title)
        }
    }

    private func toggleTitle(isExpanded: Bool, count: Int) -> LocalizedStringResource {
        isExpanded ? .searchSectionShowFewer : .searchSectionShowAll(count.formatted())
    }

    private func select(_ result: SearchResult) {
        PaeoniaHaptics.selection()
        switch result.destination {
        case let .story(id):
            openStory(id)
        case let .widgetDrawing(id):
            drawingPreview = starred.summary(for: .widgetDrawing(id))
        default:
            onSelect(result.destination)
        }
    }

    private func openStory(_ id: UUID) {
        guard let index = stories.stories.firstIndex(where: { $0.id == id }) else { return }
        storyViewer = StoryViewerContent(stories: stories.stories, startIndex: index, mode: .archive)
    }

    // MARK: - Starred

    private var starredResults: [SearchResult] {
        starred.results(people: people)
    }

    /// What this person starred, before anything is typed. It uses the rows of a search.
    @ViewBuilder
    private var starredSection: some View {
        let results = starredResults
        if !results.isEmpty {
            Section {
                ForEach(results) { result in
                    Button { select(result) } label: {
                        SearchResultRow(result: result, words: [], people: people)
                    }
                    .listRowBackground(Color.paeoniaSurfacePrimary)
                    .task {
                        if result.id == results.last?.id { await starred.loadMore() }
                    }
                }
            } header: {
                Text(.favoritesSectionTitle)
            }
        }
    }

    // MARK: - Empty states

    @ViewBuilder
    private var placeholder: some View {
        switch viewModel.phase {
        case .idle where !starredResults.isEmpty:
            EmptyView()
        case .idle:
            PaeoniaEmptyStateView(
                title: .searchIdleTitle,
                message: .searchIdleMessage,
                systemImage: "magnifyingglass"
            )
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        case .searching where viewModel.results.isEmpty:
            ProgressView()
                .tint(.paeoniaAccentPrimary)
        case .finished where viewModel.results.isEmpty:
            if let problem = viewModel.onlineProblem {
                PaeoniaLoadFailureView(failure: problem, offlineMessage: .searchOfflineMessage) {
                    retryButton
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            } else {
                PaeoniaEmptyStateView(
                    title: .searchEmptyTitle,
                    message: .searchEmptyMessage(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)),
                    systemImage: "magnifyingglass"
                )
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            }
        default:
            EmptyView()
        }
    }

    private var retryButton: some View {
        Button(action: viewModel.retry) {
            Text(.commonTryAgain)
        }
        .buttonStyle(.bordered)
        .tint(.paeoniaAccentPrimary)
    }

    private func partialMessage(for problem: PaeoniaFailure) -> LocalizedStringResource {
        problem == .offline ? .searchPartialOffline : .searchPartialFailed
    }

    /// Tells that answers and chats are missing from the matches, and offers another try.
    private func onlineProblemSection(_ problem: PaeoniaFailure) -> some View {
        Section {
            HStack(spacing: PaeoniaSpacing.space12) {
                Image(systemName: problem == .offline ? "wifi.slash" : "exclamationmark.circle")
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
                Text(partialMessage(for: problem))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                Spacer(minLength: 0)
                Button(action: viewModel.retry) { Text(.commonTryAgain) }
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .buttonStyle(.plain)
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
    }
}

private extension SearchResultKind {
    var title: LocalizedStringResource {
        switch self {
        case .memory: .searchSectionMemories
        case .question: .searchSectionQuestions
        case .answer: .searchSectionAnswers
        case .message: .searchSectionMessages
        case .story: .searchSectionStories
        case .storyChain: .searchSectionStoryChain
        case .drawing: .favoritesRowDrawing
        case .round: .gamesDrawAndGuessName
        case .creature: .exquisiteCorpseName
        }
    }
}
