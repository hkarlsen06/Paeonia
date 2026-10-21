import Foundation

/// A favorite or an unfavorite waiting in the send queue.
nonisolated struct FavoriteWritePayload: Codable, Equatable, Sendable {
    let target: FavoriteTarget
    let favorited: Bool
    let createdAt: Date

    /// Writes of one item share a scope, and go in the order they were made.
    static func scope(for target: FavoriteTarget) -> String {
        "favorite:\(target.kind.rawValue):\(target.id.uuidString.lowercased())"
    }
}
