import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

// MARK: - Gateway requests

/// Answers every request to its host with `{"status":"success","value":[]}` and
/// records the endpoint and body.
private final class DailyGatewayStubProtocol: URLProtocol, @unchecked Sendable {
    static let recorded = LockedBox<[(path: String, body: Data)]>([])

    static var requests: [(path: String, body: [String: Any])] {
        recorded.value.map { ($0.path, (try? JSONSerialization.jsonObject(with: $0.body)) as? [String: Any] ?? [:]) }
    }

    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        guard let url = request.url, let stream = request.httpBodyStream else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        stream.open()
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        stream.close()
        Self.recorded.mutate { $0.append((url.path(), data)) }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data(#"{"status":"success","value":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct DailyChallengeGatewayRequestTests {
    private func makeGateway() -> LiveDailyChallengeGateway {
        DailyGatewayStubProtocol.recorded.mutate { $0.removeAll() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DailyGatewayStubProtocol.self]
        let client = PaeoniaConvexClient(
            deploymentURL: URL(string: "https://daily.test") ?? URL(fileURLWithPath: "/"),
            session: URLSession(configuration: configuration),
            tokenProvider: { "token" }
        )
        return LiveDailyChallengeGateway(client: client)
    }

    @Test func todaysSnapshotIsReadWithAQueryAndAFreshDayKey() async throws {
        let gateway = makeGateway()

        _ = try await gateway.loadTodaySnapshot()
        _ = try await gateway.loadTodaySnapshot()

        let requests = DailyGatewayStubProtocol.requests
        let request = try #require(requests.first)
        #expect(request.path == "/api/query")
        #expect(request.body["path"] as? String == "daily:get_today_daily_challenge_snapshot")
        let keys = requests.compactMap { ($0.body["args"] as? [String: Any])?["p_day_key"] as? String }
        // A key per local date could be served a result cached before the couple's
        // day ended (its boundary is the westmost partner's midnight, not this
        // phone's). Every load uses a key no earlier load used.
        #expect(keys.count == 2)
        #expect(Set(keys).count == 2)
    }

    @Test func startAndShuffleStayMutations() async throws {
        let gateway = makeGateway()
        let operation = dailyFixedClientOperation()

        _ = try await gateway.startDailyChallenge(operation: operation)
        _ = try await gateway.shuffleQuestion(slotNumber: 1, operation: operation)

        let requests = DailyGatewayStubProtocol.requests
        #expect(requests.map(\.path) == ["/api/mutation", "/api/mutation"])
        #expect(requests.map { $0.body["path"] as? String } == [
            "daily:start_daily_challenge_snapshot",
            "daily:shuffle_daily_question_snapshot",
        ])
    }
}
