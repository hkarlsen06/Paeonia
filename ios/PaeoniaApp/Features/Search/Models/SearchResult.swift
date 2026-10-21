import Foundation

/// The groups of search results, in the order the screen lists them.
nonisolated enum SearchResultKind: Int, CaseIterable, Identifiable, Sendable {
    case memory
    case question
    case answer
    case message
    case story
    case storyChain
    // The kinds below come from the starred list only. A search does not find them.
    case drawing
    case round
    case creature

    var id: Int { rawValue }

    /// The tile symbol of a result whose kind has no photo to show.
    var systemImage: String {
        switch self {
        case .memory: "heart.fill"
        case .question: "questionmark.bubble.fill"
        case .answer: "text.quote"
        case .message: "bubble.left.fill"
        case .story: "circle.dashed"
        case .storyChain: "text.book.closed.fill"
        case .drawing: "scribble"
        case .round: "pencil.and.scribble"
        case .creature: "pawprint.fill"
        }
    }
}

/// Where a tap on a result goes. `MainTabView+Search` opens each one.
nonisolated enum SearchDestination: Hashable, Sendable {
    case memory(UUID)
    /// A memory with its comments open. A chat message on a memory opens this.
    case memoryComments(UUID)
    /// A question's page with its answers and chat.
    case question(UUID)
    case story(UUID)
    /// A story with its replies open. A chat message on a story opens this.
    case storyReplies(UUID)
    case storyChain(UUID)
    // The destinations below come from the starred list only.
    /// A drawing from the widget. The Search sheet shows it large.
    case widgetDrawing(UUID)
    case drawAndGuessRound(UUID)
    case exquisiteCorpseFigure(UUID)
}

/// One match, with what its row shows. A result carries finished text so the row does no work.
nonisolated struct SearchResult: Identifiable, Hashable, Sendable {
    let kind: SearchResultKind
    /// The id of the matched row, so a list keeps a result's identity between searches.
    let key: UUID
    /// The first line: a memory's title, a question's wording, or the words someone wrote.
    let title: String?
    /// The second line, such as a memory's note or the question an answer belongs to.
    let detail: String?
    /// A topic's name, shown after the date.
    let label: String?
    let authorUserID: UUID?
    let date: Date?
    /// True when `date` is midnight UTC of a calendar day, which has no time zone. False for a moment.
    let dateIsCalendarDay: Bool
    let photoAssetID: UUID?
    let destination: SearchDestination

    var id: String { "\(kind.rawValue)-\(key.uuidString)" }

    init(
        kind: SearchResultKind,
        key: UUID,
        title: String? = nil,
        detail: String? = nil,
        label: String? = nil,
        authorUserID: UUID? = nil,
        date: Date? = nil,
        dateIsCalendarDay: Bool = false,
        photoAssetID: UUID? = nil,
        destination: SearchDestination
    ) {
        self.kind = kind
        self.key = key
        self.title = title
        self.detail = detail
        self.label = label
        self.authorUserID = authorUserID
        self.date = date
        self.dateIsCalendarDay = dateIsCalendarDay
        self.photoAssetID = photoAssetID
        self.destination = destination
    }
}

/// The matches of one search, grouped by kind.
nonisolated struct SearchResults: Equatable, Sendable {
    private(set) var byKind: [SearchResultKind: [SearchResult]] = [:]

    static let empty = SearchResults()

    init(_ results: [SearchResult] = []) {
        byKind = Dictionary(grouping: results, by: \.kind)
    }

    var isEmpty: Bool {
        byKind.values.allSatisfy(\.isEmpty)
    }

    func results(of kind: SearchResultKind) -> [SearchResult] {
        byKind[kind] ?? []
    }

    /// The kinds that have matches, in listing order.
    var kinds: [SearchResultKind] {
        SearchResultKind.allCases.filter { !results(of: $0).isEmpty }
    }
}
