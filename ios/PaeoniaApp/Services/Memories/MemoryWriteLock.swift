import Foundation
import Synchronization

/// Serializes local writes per memory. The visit join holds the waiting and the joined memory while
/// it moves queued writes, so a command either runs before the move or finds the waiting copy gone.
nonisolated final class MemoryWriteLock: Sendable {
    static let shared = MemoryWriteLock()

    private struct State {
        var held: Set<UUID> = []
        var waiting: [CheckedContinuation<Bool, Never>] = []
    }

    private let state = Mutex(State())

    /// Waits until no other writer holds any of `memoryIDs`, then holds them until `release(_:)`.
    func take(_ memoryIDs: Set<UUID>) async {
        while await !takeOrWait(memoryIDs) {}
    }

    func release(_ memoryIDs: Set<UUID>) {
        let waiting = state.withLock { state in
            state.held.subtract(memoryIDs)
            defer { state.waiting = [] }
            return state.waiting
        }
        waiting.forEach { $0.resume(returning: false) }
    }

    /// Takes `memoryIDs` and returns true, or waits for the next release and returns false.
    private func takeOrWait(_ memoryIDs: Set<UUID>) async -> Bool {
        await withCheckedContinuation { continuation in
            let taken = state.withLock { state in
                guard state.held.isDisjoint(with: memoryIDs) else {
                    state.waiting.append(continuation)
                    return false
                }
                state.held.formUnion(memoryIDs)
                return true
            }
            if taken { continuation.resume(returning: true) }
        }
    }
}
