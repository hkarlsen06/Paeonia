@preconcurrency import ConvexMobile
import Foundation

/// One item from a live subscription.
nonisolated enum LiveResult<Value: Sendable>: Sendable {
    /// The query ran and returned a new result. The first value is the current
    /// result, and later values arrive whenever the data changes on the server.
    case value(Value)
    /// The subscription dropped or one update could not be read. The service
    /// has already scheduled a new subscription (or kept the old one), so
    /// consumers log or surface this and keep iterating.
    case failure(any Error)
}

nonisolated enum LiveQueryError: Error, Equatable, Sendable {
    /// No live client exists: the build has no Convex URL or Clerk key.
    case unavailable
    /// The socket layer failed (not a function error).
    case transport(String)
    /// The subscription ended without an error.
    case ended
    /// A result arrived but did not decode into the requested type.
    case decoding(String)
    /// An argument could not be encoded.
    case invalidArguments(String)
}

/// Opens one raw subscription. The production implementation wraps ConvexMobile.
/// Tests substitute a scripted transport.
nonisolated protocol LiveQueryTransport: Sendable {
    /// Streams every result as normalized JSON text (see `LiveJSON`).
    /// `args` holds each argument already encoded as a JSON fragment. The stream
    /// throws when the subscription fails and stops delivering when cancelled.
    func updates(path: String, args: [String: String]) -> AsyncThrowingStream<Data, any Error>
}

/// Delay between resubscribe attempts: doubles from `base` up to `cap`.
nonisolated struct LiveBackoff: Sendable {
    var base: Duration
    var cap: Duration

    static let standard = LiveBackoff(base: .seconds(1), cap: .seconds(30))

    func delay(forAttempt attempt: Int) -> Duration {
        var delay = base
        for _ in 0..<max(0, min(attempt, 16)) where delay < cap {
            delay *= 2
        }
        return min(delay, cap)
    }
}

/// Subscribes to Convex queries and hands feature code plain `AsyncStream`s.
///
/// Results decode with `PaeoniaConvexClient.decoder`, so the same snake_case
/// `Remote*` DTOs that decode HTTP responses decode live results.
nonisolated final class LiveQueryService: Sendable {
    private let transport: any LiveQueryTransport
    private let backoff: LiveBackoff
    private let sleep: @Sendable (Duration) async throws -> Void
    /// Scales each backoff delay, so phones that dropped together do not resubscribe together.
    private let jitter: @Sendable () -> Double

    init(
        transport: any LiveQueryTransport,
        backoff: LiveBackoff = .standard,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        jitter: @escaping @Sendable () -> Double = { .random(in: 0.5...1) }
    ) {
        self.transport = transport
        self.backoff = backoff
        self.sleep = sleep
        self.jitter = jitter
    }

    /// The backend refused the call because the couple has no access. A retry
    /// cannot fix it. The feeds start again with the new session when access returns.
    static func isPermanentRefusal(_ error: any Error) -> Bool {
        guard case .server(code: "42501", _)? = error as? PaeoniaConvexError else { return false }
        return true
    }

    /// Subscribes to the query `path` (for example `"location:get_partner_location_visibility"`).
    ///
    /// - The stream yields `.value` for every result, starting with the current one.
    /// - A failure yields `.failure`, waits with capped exponential backoff
    ///   (1 s doubling to 30 s, scaled by a random 0.5 to 1, reset by the next
    ///   value), and subscribes again. Function errors surface as
    ///   `PaeoniaConvexError.server(code:message:)`. A refusal for missing access
    ///   (`42501`) yields `.failure` once and finishes the stream.
    /// - A result that does not decode yields `.failure(LiveQueryError.decoding)`
    ///   and keeps the subscription open for the next result.
    /// - The stream finishes only when the consuming task is cancelled or the
    ///   stream is dropped. That cancels the upstream subscription.
    ///
    /// Pass numbers as `Double` (an `Int` encodes as a Convex int64 and fails a
    /// `v.number()` validator) and omit optional keys instead of passing `nil`.
    func subscribe<Value: Decodable & Sendable>(
        _ path: String,
        args: [String: ConvexEncodable?] = [:],
        as type: Value.Type = Value.self
    ) -> AsyncStream<LiveResult<Value>> {
        let encodedArgs: [String: String]
        do {
            encodedArgs = try args.mapValues { try $0?.convexEncode() ?? "null" }
        } catch {
            let failure = LiveQueryError.invalidArguments(String(describing: error))
            return AsyncStream { continuation in
                continuation.yield(.failure(failure))
                continuation.finish()
            }
        }

        return AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            let task = Task {
                await run(path: path, args: encodedArgs, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run<Value: Decodable & Sendable>(
        path: String,
        args: [String: String],
        continuation: AsyncStream<LiveResult<Value>>.Continuation
    ) async {
        var attempt = 0
        while !Task.isCancelled {
            var failure: any Error = LiveQueryError.ended
            do {
                for try await data in transport.updates(path: path, args: args) {
                    attempt = 0
                    do {
                        continuation.yield(.value(try PaeoniaConvexClient.decoder.decode(Value.self, from: data)))
                    } catch {
                        continuation.yield(.failure(LiveQueryError.decoding(String(describing: error))))
                    }
                }
            } catch {
                failure = error
            }

            guard !Task.isCancelled else {
                return
            }
            continuation.yield(.failure(failure))
            if Self.isPermanentRefusal(failure) {
                return
            }
            do {
                try await sleep(backoff.delay(forAttempt: attempt) * jitter())
            } catch {
                return
            }
            attempt += 1
        }
    }
}
