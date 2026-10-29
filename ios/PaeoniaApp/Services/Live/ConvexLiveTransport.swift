import Combine
@preconcurrency import ConvexMobile
import Foundation
import Observation

/// `LiveQueryTransport` backed by ConvexMobile.
nonisolated struct ConvexLiveTransport: LiveQueryTransport {
    let connection: LiveConvexConnection

    func updates(path: String, args: [String: String]) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            let handle = SubscriptionHandle()
            let task = Task { @MainActor in
                guard let client = await connection.authenticatedClient() else {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: LiveQueryError.unavailable)
                    }
                    return
                }
                // Cancellation can land while waiting for sign-in. Do not subscribe then.
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                handle.set(Self.attach(client: client, path: path, args: args, to: continuation))
                for await state in Observations({ connection.connectionState }) {
                    guard !Task.isCancelled else { return }
                    if state != .connected {
                        continuation.finish(throwing: LiveQueryError.unavailable)
                        return
                    }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                handle.cancel()
            }
        }
    }

    /// Subscribes and forwards results. This is `nonisolated` so the Combine
    /// closures run on ConvexMobile's own threads without a main-actor check.
    private nonisolated static func attach(
        client: ConvexClient,
        path: String,
        args: [String: String],
        to continuation: AsyncThrowingStream<Data, any Error>.Continuation
    ) -> AnyCancellable {
        let encoded = args.mapValues { PreEncodedArgument(json: $0) as ConvexEncodable? }
        return client
            .subscribe(to: path, with: encoded, yielding: LiveJSON.self)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        continuation.finish()
                    case let .failure(error):
                        continuation.finish(throwing: ConvexLiveErrorMapping.map(error))
                    }
                },
                receiveValue: { json in
                    do {
                        continuation.yield(try json.normalizedData())
                    } catch {
                        continuation.finish(throwing: LiveQueryError.decoding(String(describing: error)))
                    }
                }
            )
    }

    /// Holds the Combine subscription so termination can cancel it from any thread.
    private nonisolated final class SubscriptionHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var cancellable: AnyCancellable?
        private var isCancelled = false

        func set(_ newValue: AnyCancellable) {
            lock.withLock {
                if isCancelled {
                    newValue.cancel()
                } else {
                    cancellable = newValue
                }
            }
        }

        func cancel() {
            lock.withLock {
                isCancelled = true
                cancellable?.cancel()
                cancellable = nil
            }
        }
    }

    /// An argument that is already JSON text.
    private struct PreEncodedArgument: ConvexEncodable {
        let json: String

        func convexEncode() throws -> String {
            json
        }
    }
}

nonisolated enum ConvexLiveErrorMapping {
    /// Turns a ConvexMobile error into the errors the HTTP client throws, so
    /// callers match on `PaeoniaConvexError.server(code:message:)` in both paths.
    static func map(_ error: ClientError) -> any Error {
        switch error {
        case let .ConvexError(data):
            // Our functions throw `ConvexError({ code, message })`.
            struct Payload: Decodable {
                let code: String?
                let message: String?
            }
            if let payload = try? JSONDecoder().decode(Payload.self, from: Data(data.utf8)) {
                return PaeoniaConvexError.server(code: payload.code, message: payload.message ?? data)
            }
            if let text = try? JSONDecoder().decode(String.self, from: Data(data.utf8)) {
                return PaeoniaConvexError.server(code: nil, message: text)
            }
            return PaeoniaConvexError.server(code: nil, message: data)
        case let .ServerError(msg):
            return PaeoniaConvexError.server(code: nil, message: msg)
        case let .InternalError(msg):
            return LiveQueryError.transport(msg)
        }
    }
}
