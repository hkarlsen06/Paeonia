import CryptoKit
import Foundation

/// The couple's conversation about a game, across all its rounds.
nonisolated struct GameChatSubject: Codable, Hashable, Sendable, Identifiable {
    let coupleID: UUID
    let kind: GameKind

    var id: UUID {
        let key = "game-chat:\(coupleID.uuidString.lowercased()):\(kind.rawValue)"
        let bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}

nonisolated struct GameChatResultReference: Codable, Hashable, Sendable, Identifiable {
    let source: GameConversationSource
    let finishedAt: Date
    let key: String
    var id: UUID { source.id }
    enum CodingKeys: String, CodingKey {
        case source, key
        case finishedAt = "finished_at"
    }
}

nonisolated struct GameChatTimelineCursor: Codable, Equatable, Sendable {
    let at: Date
    let itemKind: String
    let key: String
    enum CodingKeys: String, CodingKey {
        case at, key
        case itemKind = "item_kind"
    }
}

nonisolated struct GameChatTimeline: Codable, Equatable, Sendable {
    var threadID: UUID?
    var messages: [ThreadChatMessage]
    var results: [GameChatResultReference]
    var hasMore: Bool
    var nextBefore: GameChatTimelineCursor?

    static let empty = Self(messages: [], results: [], hasMore: false)

    /// Absence is meaningful only inside the interval this server page covers.
    func confirmsRemoval(of reference: GameChatResultReference) -> Bool {
        guard !results.contains(where: { $0.id == reference.id }) else { return false }
        guard hasMore else { return true }
        guard let nextBefore else { return false }
        return (reference.finishedAt, "result", reference.key)
            >= (nextBefore.at, nextBefore.itemKind, nextBefore.key)
    }

    /// A refresh keeps an older cached range only if both pages overlap.
    func merging(_ page: Self, older: Bool) -> Self {
        let overlaps =
            !Set(messages.map(\.id)).isDisjoint(with: page.messages.map(\.id))
            || !Set(results.map(\.id)).isDisjoint(with: page.results.map(\.id))
        let keepOlder = !older && page.hasMore && overlaps
        func beforeBoundary(_ at: Date, kind: String, key: String) -> Bool {
            guard let boundary = page.nextBefore else { return false }
            return (at, kind, key) < (boundary.at, boundary.itemKind, boundary.key)
        }
        let keptMessages = messages.filter {
            older
                || keepOlder
                    && beforeBoundary($0.createdAt, kind: "message", key: $0.id.uuidString.lowercased())
        }
        let keptResults = results.filter {
            older || keepOlder && beforeBoundary($0.finishedAt, kind: "result", key: $0.key)
        }
        let allMessages = ThreadChatMessage.visibleOrdered(
            remote: keptMessages + page.messages, optimistic: [])
        let allResults = Dictionary(
            (keptResults + page.results).map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        ).values.sorted {
            ($0.finishedAt, $0.key) < ($1.finishedAt, $1.key)
        }
        return Self(
            threadID: page.threadID ?? threadID, messages: allMessages, results: allResults,
            hasMore: keepOlder ? hasMore : page.hasMore,
            nextBefore: keepOlder ? nextBefore : page.nextBefore)
    }
}
