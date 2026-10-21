import Foundation

/// What the phone already holds and searches without a connection.
nonisolated struct SearchLocalContent: Sendable {
    var memories: [MemoryRecord] = []
    var stories: [Story] = []
}

/// Search over memories (title, notes and place) and story captions. Both sit in the local
/// store in full, so this works offline and needs no server index.
nonisolated enum LocalContentSearch {
    /// The most results of one kind.
    static let limitPerKind = 60

    static func search(_ query: SearchQuery, in content: SearchLocalContent) -> [SearchResult] {
        guard query.isSearchable else { return [] }
        return memoryResults(query, memories: content.memories) + storyResults(query, stories: content.stories)
    }

    private static func memoryResults(_ query: SearchQuery, memories: [MemoryRecord]) -> [SearchResult] {
        let matches = memories.compactMap { record -> SearchResult? in
            let memory = record.snapshot
            let notes = [memory.ownNote, memory.partnerNote]
                .compactMap { $0?.isVisible == true ? $0?.body : nil }
                .filter { !$0.isEmpty }
            let place = memory.place?.nameAndCity
            let parts = [memory.title].compactMap(\.self) + notes + [place].compactMap(\.self)
            guard SearchText.containsEveryWord(query.words, in: parts.joined(separator: "\n")) else { return nil }

            // The line under the title is the note or place that matched, else the first note.
            let detailSource = (notes + [place].compactMap(\.self))
                .first { text in query.words.contains { SearchText.containsEveryWord([$0], in: text) } }
                ?? notes.first
            let day = MemoryTimeline.parseLocalDate(memory.memoryDate)
            return SearchResult(
                kind: .memory,
                key: memory.memoryID,
                title: memory.title,
                detail: detailSource.map { SearchText.snippet(of: $0, words: query.words) },
                label: memory.place?.shortName,
                date: day ?? memory.createdAt,
                dateIsCalendarDay: day != nil,
                photoAssetID: memory.visibleMediaAssetIDs.first,
                destination: .memory(memory.memoryID)
            )
        }
        return Array(matches.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(limitPerKind))
    }

    private static func storyResults(_ query: SearchQuery, stories: [Story]) -> [SearchResult] {
        let matches = stories.filter { story in
            story.caption.map { SearchText.containsEveryWord(query.words, in: $0) } ?? false
        }
        return matches
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limitPerKind)
            .map { story in
                SearchResult(
                    kind: .story,
                    key: story.id,
                    title: story.caption.map { SearchText.snippet(of: $0, words: query.words) },
                    authorUserID: story.authorUserID,
                    date: story.createdAt,
                    photoAssetID: story.mediaAssetID,
                    destination: .story(story.id)
                )
            }
    }
}
