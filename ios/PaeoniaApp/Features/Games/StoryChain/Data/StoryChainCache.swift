import Foundation

/// What this phone keeps of Story Chain for one signed-in person, so the game
/// shows something at launch and offline. `state` is the last result of
/// `storyChain:get_story_chain`. The notices are only ever local.
nonisolated struct StoryChainLocalDocument: GamesPersistedDocument {
    var state: RemoteStoryChainState?
    /// "Our stories": the newest finished stories, the first page of "All".
    var historyFirstPage: RemoteStoryChainHistoryPage?
    /// What the server last said about this person's star on a story. It covers
    /// the stories that are not in `state`.
    var stars: [UUID: Bool] = [:]
    var notices: [GameStoredNotice] = []
    /// What the composer held when it was last saved, so a relaunch loses
    /// nothing. It goes back into the next composer, whatever story that is.
    var draft: String?
    /// The words of lines the server refused for good, oldest first. The next
    /// composer takes them, so a refused line is never lost.
    var rescuedLines: [String] = []
}

/// The Story Chain cache. The live feed writes `state`, and the screens read it.
/// Every method is keyed by the owner, so another account on this phone never
/// reads this person's story. Counting a send the server keeps refusing is done
/// by the shared Games cache (`GamesCaching.recordUnexplainedRefusal`).
protocol StoryChainCaching: Actor {
    func document(ownerUserID: UUID) -> StoryChainLocalDocument
    /// The live feed's write. It wins over every one-shot read that started
    /// before it, unless it is older than the cached state (see `isOlder(than:)`).
    func saveState(_ state: RemoteStoryChainState, ownerUserID: UUID)
    /// Takes a ticket for a one-shot read that is about to start.
    func beginFetch() -> Int
    /// Saves a one-shot read, unless a live write, a purge, or a read that
    /// started later was saved after `ticket` was taken. A read that has a higher
    /// game version than the kept state is saved anyway, because a live write can
    /// carry a state from before the read. Returns whether it saved.
    @discardableResult
    func saveFetchedState(_ state: RemoteStoryChainState, ownerUserID: UUID, ticket: Int) -> Bool
    /// Keeps the first page of "Our stories".
    func saveHistoryFirstPage(_ page: RemoteStoryChainHistoryPage, ownerUserID: UUID)
    /// Keeps what the server said about this person's star on stories.
    func saveStars(_ stars: [UUID: Bool], ownerUserID: UUID)
    func recordNotice(_ notice: GameStoredNotice, ownerUserID: UUID)
    /// Keeps the composer's text, or forgets it with nil.
    func saveDraft(_ draft: String?, ownerUserID: UUID)
    /// Keeps the words of a line the server refused, for the next composer.
    func rescueLines(_ lines: [String], ownerUserID: UUID)
    /// Saves `composerText` with the rescued lines added as the draft and forgets
    /// the rescued lines, in one step, so no crash in between can lose them.
    /// Returns the rescued words joined, or nil when nothing was rescued.
    func takeRescuedLines(into composerText: String, ownerUserID: UUID) -> String?
    /// Returns the notices and forgets them.
    func takeNotices(ownerUserID: UUID) -> [GameStoredNotice]
    /// Called when the person leaves the paired state, so private content does not
    /// stay on the phone. A one-shot read still on its way is not saved after it.
    func clearAll()
}

extension StoryChainCaching {
    /// Reads the server's state once and caches it, unless the live feed cached
    /// something newer while the request ran. Returns false when the answer is
    /// for another person, which is not cached.
    nonisolated func fetchState(from gateway: any StoryChainGateway, ownerUserID: UUID) async throws -> Bool {
        let ticket = await beginFetch()
        let loaded = try await gateway.loadStoryChain()
        guard loaded.userID == ownerUserID else { return false }
        await saveFetchedState(loaded, ownerUserID: ownerUserID, ticket: ticket)
        return true
    }
}

// MARK: - Rules shared by the file and in-memory caches

nonisolated extension StoryChainLocalDocument {
    private static let maxStars = 500

    /// Takes a state from the server unless it is older than the one kept.
    /// Returns whether it took it. The stars it carries become the server's
    /// values, so a story that leaves the state keeps its star.
    mutating func accept(_ newState: RemoteStoryChainState) -> Bool {
        if let state, newState.isOlder(than: state) {
            return false
        }
        state = newState
        mergeStars(newState.starValues)
        return true
    }

    /// The rescued lines join the composer's text, which becomes the saved draft.
    /// Returns the rescued words joined.
    mutating func takeRescuedLines(into composerText: String) -> String? {
        guard !rescuedLines.isEmpty else { return nil }
        let rescued = rescuedLines.joined(separator: " ")
        draft = [composerText, rescued].filter { !$0.isEmpty }.joined(separator: " ")
        rescuedLines = []
        return rescued
    }

    mutating func record(_ notice: GameStoredNotice) {
        if !notices.contains(notice) {
            notices.append(notice)
        }
    }

    private mutating func mergeStars(_ values: [UUID: Bool]) {
        stars.merge(values) { _, new in new }
        if stars.count > Self.maxStars {
            // A story with no entry reads as not starred, so the unstarred ones go first.
            stars = stars.filter(\.value)
        }
    }

    /// Takes the server's answer for these stories everywhere this document
    /// holds them, so the state, the first page and the list never disagree.
    mutating func saveStars(_ values: [UUID: Bool]) {
        mergeStars(values)
        state?.apply(stars: values)
        historyFirstPage = historyFirstPage?.applying(stars: values)
    }
}

nonisolated extension RemoteStoryChainState {
    /// The finished stories of the state and whether this person starred each.
    /// A story that is not finished can't be starred, so it says nothing.
    var starValues: [UUID: Bool] {
        Dictionary(
            [currentStory, previousStory].compactMap(\.self)
                .filter { $0.state == .finished }
                .map { ($0.id, $0.starredByMe) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Takes the server's answer for the person's star on the stories it carries.
    mutating func apply(stars: [UUID: Bool]) {
        if let value = currentStory.flatMap({ stars[$0.id] }) {
            currentStory?.starredByMe = value
        }
        if let value = previousStory.flatMap({ stars[$0.id] }) {
            previousStory?.starredByMe = value
        }
    }
}

nonisolated extension RemoteStoryChainHistoryPage {
    /// The star state of every story on the page.
    var starValues: [UUID: Bool] {
        Dictionary(stories.map { ($0.id, $0.starredByMe) }, uniquingKeysWith: { _, last in last })
    }

    func applying(stars: [UUID: Bool]) -> RemoteStoryChainHistoryPage {
        RemoteStoryChainHistoryPage(
            stories: stories.map { story in
                var changed = story
                changed.starredByMe = stars[story.id] ?? story.starredByMe
                return changed
            },
            nextBeforeStoryNumber: nextBeforeStoryNumber
        )
    }
}

// MARK: - On disk

/// One JSON file per signed-in person under Application Support.
actor FileStoryChainCache: StoryChainCaching {
    static let shared = FileStoryChainCache()

    private var store: GamesDocumentStore<StoryChainLocalDocument>
    private var order = GamesStateWriteOrder()

    init(directoryURL: URL = FileStoryChainCache.defaultDirectoryURL()) {
        store = GamesDocumentStore(directoryURL: directoryURL, schemaVersion: 3)
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        GamesDocumentStore<StoryChainLocalDocument>.defaultDirectoryURL(named: "StoryChainCache")
    }

    func document(ownerUserID: UUID) -> StoryChainLocalDocument {
        store.document(ownerUserID: ownerUserID)
    }

    func saveState(_ state: RemoteStoryChainState, ownerUserID: UUID) {
        var kept = document(ownerUserID: ownerUserID)
        guard kept.accept(state) else { return }
        order.overrideFetches()
        store.save(kept, ownerUserID: ownerUserID)
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    func saveFetchedState(_ state: RemoteStoryChainState, ownerUserID: UUID, ticket: Int) -> Bool {
        var kept = document(ownerUserID: ownerUserID)
        let isNewer = kept.state.map { $0.isOlder(than: state) } ?? false
        guard kept.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        store.save(kept, ownerUserID: ownerUserID)
        return true
    }

    func saveHistoryFirstPage(_ page: RemoteStoryChainHistoryPage, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.historyFirstPage = page }
    }

    func saveStars(_ stars: [UUID: Bool], ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.saveStars(stars) }
    }

    func recordNotice(_ notice: GameStoredNotice, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.record(notice) }
    }

    func saveDraft(_ draft: String?, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.draft = draft }
    }

    func rescueLines(_ lines: [String], ownerUserID: UUID) {
        guard !lines.isEmpty else { return }
        store.update(ownerUserID: ownerUserID) { $0.rescuedLines += lines }
    }

    func takeRescuedLines(into composerText: String, ownerUserID: UUID) -> String? {
        store.update(ownerUserID: ownerUserID) { $0.takeRescuedLines(into: composerText) }
    }

    func takeNotices(ownerUserID: UUID) -> [GameStoredNotice] {
        var taken: [GameStoredNotice] = []
        store.update(ownerUserID: ownerUserID) { document in
            taken = document.notices
            document.notices = []
        }
        return taken
    }

    func clearAll() {
        order.overrideFetches()
        store.clear()
    }
}

// MARK: - In memory

/// For tests and the developer scenarios.
actor InMemoryStoryChainCache: StoryChainCaching {
    private var documents: [UUID: StoryChainLocalDocument] = [:]
    private var order = GamesStateWriteOrder()

    /// With a `state`, the owner is the state's person unless `ownerUserID` says otherwise.
    init(state: RemoteStoryChainState? = nil, ownerUserID: UUID? = nil) {
        guard let state else { return }
        var document = StoryChainLocalDocument()
        _ = document.accept(state)
        documents[ownerUserID ?? state.userID] = document
    }

    func document(ownerUserID: UUID) -> StoryChainLocalDocument {
        documents[ownerUserID] ?? StoryChainLocalDocument()
    }

    func saveState(_ state: RemoteStoryChainState, ownerUserID: UUID) {
        guard documents[ownerUserID, default: StoryChainLocalDocument()].accept(state) else { return }
        order.overrideFetches()
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    func saveFetchedState(_ state: RemoteStoryChainState, ownerUserID: UUID, ticket: Int) -> Bool {
        var document = documents[ownerUserID, default: StoryChainLocalDocument()]
        let isNewer = document.state.map { $0.isOlder(than: state) } ?? false
        guard document.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        documents[ownerUserID] = document
        return true
    }

    func saveHistoryFirstPage(_ page: RemoteStoryChainHistoryPage, ownerUserID: UUID) {
        documents[ownerUserID, default: StoryChainLocalDocument()].historyFirstPage = page
    }

    func saveStars(_ stars: [UUID: Bool], ownerUserID: UUID) {
        documents[ownerUserID, default: StoryChainLocalDocument()].saveStars(stars)
    }

    func recordNotice(_ notice: GameStoredNotice, ownerUserID: UUID) {
        documents[ownerUserID, default: StoryChainLocalDocument()].record(notice)
    }

    func saveDraft(_ draft: String?, ownerUserID: UUID) {
        documents[ownerUserID, default: StoryChainLocalDocument()].draft = draft
    }

    func rescueLines(_ lines: [String], ownerUserID: UUID) {
        documents[ownerUserID, default: StoryChainLocalDocument()].rescuedLines += lines
    }

    func takeRescuedLines(into composerText: String, ownerUserID: UUID) -> String? {
        documents[ownerUserID, default: StoryChainLocalDocument()].takeRescuedLines(into: composerText)
    }

    func takeNotices(ownerUserID: UUID) -> [GameStoredNotice] {
        let notices = documents[ownerUserID]?.notices ?? []
        documents[ownerUserID]?.notices = []
        return notices
    }

    func clearAll() {
        order.overrideFetches()
        documents = [:]
    }
}
