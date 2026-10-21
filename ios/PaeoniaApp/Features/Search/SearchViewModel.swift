import Foundation
import Observation

/// The Search screen's state. Memories and stories are searched on the phone, so their results
/// show at once and work offline. Questions, answers, chats and Story Chain stories are searched
/// on the server, after the person pauses typing. A failed server search keeps the phone's
/// results and says what is missing, so the screen never looks empty because of the connection.
@MainActor
@Observable
final class SearchViewModel {
    enum Phase: Equatable {
        /// Nothing worth searching for has been typed.
        case idle
        case searching
        case finished
    }

    var query = "" {
        didSet {
            if query != oldValue { restart() }
        }
    }

    private(set) var results = SearchResults.empty
    private(set) var phase = Phase.idle
    /// Set when the server search failed. The results then hold only the phone's matches.
    private(set) var onlineProblem: PaeoniaFailure?
    /// The words to mark in the results.
    private(set) var words: [String] = []

    @ObservationIgnored private let service: any SearchServing
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let pause: Duration
    @ObservationIgnored private var content = SearchLocalContent()
    /// True from `begin` until `end`. A reload that finishes after the screen closed is dropped,
    /// so private content never comes back into a closed Search.
    @ObservationIgnored private var isOpen = false
    @ObservationIgnored private var localResults: [SearchResult] = []
    @ObservationIgnored private var remoteResults: [SearchResult] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(
        service: any SearchServing = NoOpSearchService(),
        locale: Locale = .current,
        pause: Duration = .milliseconds(350)
    ) {
        self.service = service
        self.locale = locale
        self.pause = pause
    }

    /// Clears the last search and loads what the phone searches. Call it when the screen opens.
    func begin(loadContent: @MainActor () async -> SearchLocalContent) async {
        isOpen = true
        clear()
        query = ""
        content = await loadContent()
        // The person may have typed while the content loaded.
        if SearchQuery(query).isSearchable { restart() }
    }

    /// Drops the search and the copies of private content. Call it when the screen closes.
    func end() {
        isOpen = false
        clear()
        query = ""
        content = SearchLocalContent()
    }

    /// Reads the memories and stories again and runs the current search on them. A memory or
    /// story the partner deleted while Search is open then stops matching.
    func refreshContent(loadContent: @MainActor () async -> SearchLocalContent) async {
        guard isOpen else { return }
        let fresh = await loadContent()
        guard isOpen, !Task.isCancelled else { return }
        content = fresh
        if SearchQuery(query).isSearchable { restart() }
    }

    /// Follows writes to the memories while Search is open. Stories are followed by the screen,
    /// which watches the stories list.
    func observeMemoryChanges(loadContent: @MainActor () async -> SearchLocalContent) async {
        for await _ in LocalStoreChanges.changes(in: .memories) {
            guard !Task.isCancelled else { return }
            await refreshContent(loadContent: loadContent)
        }
    }

    /// Runs the current search again, for the "try again" after a failed server search.
    func retry() {
        restart()
    }

    private func clear() {
        searchTask?.cancel()
        localResults = []
        remoteResults = []
        results = .empty
        words = []
        phase = .idle
        onlineProblem = nil
    }

    private func restart() {
        searchTask?.cancel()
        let parsed = SearchQuery(query)
        words = parsed.words
        guard parsed.isSearchable else {
            clear()
            return
        }
        phase = .searching
        let snapshot = content
        searchTask = Task { [weak self] in
            await self?.run(parsed, content: snapshot)
        }
    }

    private func run(_ query: SearchQuery, content: SearchLocalContent) async {
        let local = await Task.detached(priority: .userInitiated) {
            LocalContentSearch.search(query, in: content)
        }.value
        guard !Task.isCancelled else { return }
        localResults = local
        publish()

        try? await Task.sleep(for: pause)
        guard !Task.isCancelled else { return }
        do {
            let response = try await service.search(query, locale: locale)
            guard !Task.isCancelled else { return }
            remoteResults = response.results
            onlineProblem = nil
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return }
            remoteResults = []
            onlineProblem = PaeoniaFailure(error)
        }
        phase = .finished
        publish()
    }

    private func publish() {
        results = SearchResults(localResults + remoteResults)
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

extension SearchViewModel {
    /// The production model: the server search runs through the signed-in Convex client, or
    /// finds nothing online when none is configured (previews and tests).
    static func live() -> SearchViewModel {
        let service: any SearchServing
        if let client = try? PaeoniaConvexClientProvider.shared.client() {
            service = LiveSearchService(client: client)
        } else {
            service = NoOpSearchService()
        }
        return SearchViewModel(service: service)
    }
}
