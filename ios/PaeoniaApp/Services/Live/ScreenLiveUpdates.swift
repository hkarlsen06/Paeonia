import Foundation

/// A subscription that lives only while one screen reads it. The data is not
/// cached for offline use, so no `LiveFeed` or store is involved. Cancelling the
/// consuming task ends the subscription.
nonisolated enum ScreenLiveUpdates {
    /// Yields `map(row)` for every result of the query `path`. Failures are
    /// dropped. `LiveQueryService` resubscribes on its own.
    static func values<Row: Decodable & Sendable, Value: Sendable>(
        _ path: String,
        as row: Row.Type,
        map: @escaping @Sendable (Row) -> Value
    ) -> AsyncStream<Value> {
        AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            let task = Task { @MainActor in
                let live = LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
                for await result in live.subscribe(path, as: row) {
                    if case let .value(value) = result {
                        continuation.yield(map(value))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
