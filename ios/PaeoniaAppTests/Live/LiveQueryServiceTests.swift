@preconcurrency import ConvexMobile
import Foundation
import Testing
@testable import PaeoniaApp

struct LiveQueryServiceTests {
    private struct Row: Decodable, Sendable, Equatable {
        let displayName: String
        let streak: Int
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case streak
            case updatedAt = "updated_at"
        }
    }

    private static let rowJSON = #"{"display_name":"Alex","streak":5,"updated_at":"2026-05-01T10:00:00.123Z"}"#

    /// Plays one script per `updates` call. A script emits values and either
    /// fails or stays open until the consumer cancels.
    private final class ScriptedTransport: LiveQueryTransport, @unchecked Sendable {
        enum Ending {
            case fail(any Error)
            case finish
            case stayOpen
        }

        struct Script {
            var values: [String]
            var ending: Ending
        }

        private let scripts: LockedBox<[Script]>
        let openedPaths = LockedBox<[String]>([])
        let openedArgs = LockedBox<[[String: String]]>([])
        let terminations = LockedBox(0)

        init(_ scripts: [Script]) {
            self.scripts = LockedBox(scripts)
        }

        func updates(path: String, args: [String: String]) -> AsyncThrowingStream<Data, any Error> {
            openedPaths.mutate { $0.append(path) }
            openedArgs.mutate { $0.append(args) }
            var script: Script?
            scripts.mutate { remaining in
                script = remaining.isEmpty ? nil : remaining.removeFirst()
            }
            return AsyncThrowingStream { continuation in
                continuation.onTermination = { [terminations] _ in
                    terminations.mutate { $0 += 1 }
                }
                guard let script else {
                    return
                }
                for value in script.values {
                    continuation.yield(Data(value.utf8))
                }
                switch script.ending {
                case let .fail(error):
                    continuation.finish(throwing: error)
                case .finish:
                    continuation.finish()
                case .stayOpen:
                    break
                }
            }
        }
    }

    private static func makeService(
        _ transport: ScriptedTransport,
        delays: LockedBox<[Duration]> = LockedBox([])
    ) -> LiveQueryService {
        LiveQueryService(
            transport: transport,
            backoff: LiveBackoff(base: .seconds(1), cap: .seconds(8)),
            sleep: { delay in
                delays.mutate { $0.append(delay) }
                try await Task.sleep(for: .milliseconds(1))
            },
            jitter: { 1 }
        )
    }

    @Test func decodesSnakeCaseFieldsDatesAndWholeNumbers() async throws {
        let transport = ScriptedTransport([.init(values: [Self.rowJSON], ending: .stayOpen)])
        let service = Self.makeService(transport)
        var iterator = service.subscribe("users:get_row", as: Row.self).makeAsyncIterator()

        let first = await iterator.next()

        guard case let .value(row)? = first else {
            Issue.record("Expected a value, got \(String(describing: first))")
            return
        }
        #expect(row.displayName == "Alex")
        #expect(row.streak == 5)
        #expect(abs(row.updatedAt.timeIntervalSince1970 - 1_777_629_600.123) < 0.001)
        #expect(transport.openedPaths.value == ["users:get_row"])
    }

    @Test func passesEncodedArgumentsToTheTransport() async {
        let transport = ScriptedTransport([.init(values: ["1"], ending: .stayOpen)])
        var iterator = Self.makeService(transport)
            .subscribe("a:b", args: ["p_note": "hi", "p_count": 3.0], as: Int.self)
            .makeAsyncIterator()

        _ = await iterator.next()

        #expect(transport.openedArgs.value == [["p_note": "\"hi\"", "p_count": "3"]])
    }

    @Test func mapsFunctionErrorsAndResubscribesWithBackoff() async {
        let serverError = PaeoniaConvexError.server(code: "53300", message: "too many requests")
        let transport = ScriptedTransport([
            .init(values: ["1"], ending: .fail(serverError)),
            .init(values: [], ending: .fail(serverError)),
            .init(values: ["2"], ending: .stayOpen),
        ])
        let delays = LockedBox<[Duration]>([])
        var iterator = Self.makeService(transport, delays: delays)
            .subscribe("a:b", as: Int.self)
            .makeAsyncIterator()

        var events: [String] = []
        while events.count < 4, let item = await iterator.next() {
            switch item {
            case let .value(number):
                events.append("value \(number)")
            case let .failure(error):
                events.append(error as? PaeoniaConvexError == serverError ? "server error" : "other error")
            }
        }

        #expect(events.prefix(4) == ["value 1", "server error", "server error", "value 2"])
        // The first retry follows a value, so the attempt counter reset. The
        // second retry follows a failure with no value, so it waits longer.
        #expect(delays.value.prefix(2) == [.seconds(1), .seconds(2)])
        #expect(transport.openedPaths.value.count == 3)
    }

    @Test func aStreamThatEndsWithoutAnErrorIsResubscribed() async {
        let transport = ScriptedTransport([
            .init(values: ["1"], ending: .finish),
            .init(values: ["2"], ending: .stayOpen),
        ])
        var iterator = Self.makeService(transport).subscribe("a:b", as: Int.self).makeAsyncIterator()

        var events: [String] = []
        while events.count < 3, let item = await iterator.next() {
            switch item {
            case let .value(number):
                events.append("value \(number)")
            case let .failure(error):
                events.append(error as? LiveQueryError == .ended ? "ended" : "other")
            }
        }

        #expect(events == ["value 1", "ended", "value 2"])
    }

    @Test func aResultThatDoesNotDecodeIsReportedAndTheSubscriptionContinues() async {
        let transport = ScriptedTransport([
            .init(values: [#"{"unexpected":true}"#, Self.rowJSON], ending: .stayOpen),
        ])
        var iterator = Self.makeService(transport).subscribe("a:b", as: Row.self).makeAsyncIterator()

        let first = await iterator.next()
        let second = await iterator.next()

        guard case let .failure(error)? = first, case .decoding? = error as? LiveQueryError else {
            Issue.record("Expected a decoding failure, got \(String(describing: first))")
            return
        }
        guard case .value? = second else {
            Issue.record("Expected a value after the failure, got \(String(describing: second))")
            return
        }
        #expect(transport.openedPaths.value.count == 1)
    }

    @Test func cancellingTheConsumerCancelsTheUpstreamSubscription() async {
        let transport = ScriptedTransport([.init(values: ["1"], ending: .stayOpen)])
        let service = Self.makeService(transport)
        let consumer = Task {
            for await _ in service.subscribe("a:b", as: Int.self) {}
        }
        #expect(await waitUntil { transport.openedPaths.value.count == 1 })

        consumer.cancel()
        await consumer.value

        #expect(await waitUntil { transport.terminations.value >= 1 })
        // No resubscribe after cancellation.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(transport.openedPaths.value.count == 1)
    }

    @Test func cancellingDuringBackoffStopsWithoutResubscribing() async {
        let transport = ScriptedTransport([
            .init(values: [], ending: .fail(PaeoniaConvexError.notAuthenticated)),
        ])
        let service = LiveQueryService(
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        let failures = LockedBox(0)
        let consumer = Task {
            for await item in service.subscribe("a:b", as: Int.self) {
                if case .failure = item {
                    failures.mutate { $0 += 1 }
                }
            }
        }
        #expect(await waitUntil { failures.value == 1 })

        consumer.cancel()
        await consumer.value

        #expect(transport.openedPaths.value.count == 1)
    }

    // MARK: - Error mapping

    @Test func convexErrorPayloadMapsToServerCodeAndMessage() {
        let mapped = ConvexLiveErrorMapping.map(
            .ConvexError(data: #"{"code":"23514","message":"stale location update"}"#)
        )

        #expect(mapped as? PaeoniaConvexError == .server(code: "23514", message: "stale location update"))
    }

    @Test func convexErrorWithAStringPayloadKeepsTheText() {
        let mapped = ConvexLiveErrorMapping.map(.ConvexError(data: #""plain failure""#))

        #expect(mapped as? PaeoniaConvexError == .server(code: nil, message: "plain failure"))
    }

    @Test func serverAndInternalErrorsMapToTheirOwnCases() {
        #expect(
            ConvexLiveErrorMapping.map(.ServerError(msg: "Uncaught Error: boom")) as? PaeoniaConvexError
                == .server(code: nil, message: "Uncaught Error: boom")
        )
        #expect(
            ConvexLiveErrorMapping.map(.InternalError(msg: "socket closed")) as? LiveQueryError
                == .transport("socket closed")
        )
    }
}

extension LiveQueryServiceTests {
    @Test func aRefusalForMissingAccessEndsTheStreamWithoutRetrying() async {
        let refusal = PaeoniaConvexError.server(code: "42501", message: "active entitled couple access is required")
        let transport = ScriptedTransport([
            .init(values: ["1"], ending: .fail(refusal)),
            .init(values: ["2"], ending: .stayOpen),
        ])
        let delays = LockedBox<[Duration]>([])
        let stream = Self.makeService(transport, delays: delays).subscribe("a:b", as: Int.self)

        var events: [String] = []
        for await item in stream {
            switch item {
            case let .value(number):
                events.append("value \(number)")
            case let .failure(error):
                events.append(error as? PaeoniaConvexError == refusal ? "refused" : "other error")
            }
        }

        #expect(events == ["value 1", "refused"])
        #expect(delays.value.isEmpty)
        #expect(transport.openedPaths.value.count == 1)
    }
}
