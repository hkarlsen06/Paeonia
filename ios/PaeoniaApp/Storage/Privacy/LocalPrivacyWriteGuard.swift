import Foundation

/// Opt-in protection for private metadata saves whose editor can outlive sign-out or relationship removal.
/// The same lock orders their durable enqueue and the start of the owner's privacy purge.
nonisolated final class LocalPrivacyWriteGuard: @unchecked Sendable {
    static let shared = LocalPrivacyWriteGuard()

    nonisolated struct Token: Equatable, Sendable {
        fileprivate let ownerUserID: UUID
        fileprivate let generation: Int
    }

    nonisolated enum WriteError: Error { case purged }
    private let lock = NSLock()
    private var generations: [UUID: Int] = [:]

    func token(ownerUserID: UUID) -> Token {
        lock.withLock { Token(ownerUserID: ownerUserID, generation: generations[ownerUserID, default: 0]) }
    }

    func invalidate(ownerUserID: UUID) {
        lock.withLock { generations[ownerUserID, default: 0] += 1 }
    }

    func isCurrent(_ token: Token) -> Bool {
        lock.withLock { generations[token.ownerUserID, default: 0] == token.generation }
    }

    func write<Value>(ownerUserID: UUID, token: Token?, _ body: () throws -> Value) throws -> Value {
        // Other outbox operations keep their existing behavior.
        guard let token else { return try body() }
        return try lock.withLock {
            guard token.ownerUserID == ownerUserID, generations[ownerUserID, default: 0] == token.generation
            else { throw WriteError.purged }
            return try body()
        }
    }
}
