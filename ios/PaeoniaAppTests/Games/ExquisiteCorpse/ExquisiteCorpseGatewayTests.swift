import Foundation
import Testing
@testable import PaeoniaApp

/// What `LiveExquisiteCorpseGateway` sends and reads. The names and the keys are the contract with
/// `backend/convex/exquisiteCorpse.ts`, so a wrong spelling would only show as a refusal on a device.
/// The stub keeps one shared handler, so these tests run one at a time.
@Suite(.serialized)
struct ExquisiteCorpseGatewayTests {
    private typealias Fixture = ExquisiteCorpseFixture

    private let operation = SyncClientOperation(
        id: UUID(uuidString: "0A0A0A0A-0000-4000-8000-000000000001") ?? UUID(),
        clientID: UUID(uuidString: "0A0A0A0A-0000-4000-8000-000000000002") ?? UUID(),
        clientSequence: 42,
        localCreatedAt: Fixture.now
    )

    // MARK: Sending a part

    @Test func aPartSendsEveryIdAndTheOperation() async throws {
        let recorder = CorpseRequestRecorder()
        CorpseStubURLProtocol.handler = { request in
            recorder.record(request)
            return Data(Self.submitAnswer.utf8)
        }
        let head = Fixture.queuedPart(figure: 2, partIndex: 0, idea: Fixture.idea("a grandma"))

        let result = try await Self.makeGateway().submitExquisiteCorpsePart(
            head,
            drawingAssetID: Fixture.drawingAssetID,
            stripAssetID: Fixture.stripAssetID,
            operation: operation
        )

        #expect(result.partID.uuidString == "66666666-6666-4666-8666-666666666666")
        #expect(!result.figureFinished)
        let request = try #require(recorder.last)
        #expect(request.url?.path == "/api/mutation")
        let body = try Self.body(of: request)
        #expect(body["path"] as? String == "exquisiteCorpse:submit_exquisite_corpse_part")
        let args = try #require(body["args"] as? [String: Any])
        #expect(args["p_game_id"] as? String == head.gameID.uuidString)
        #expect(args["p_figure_id"] as? String == head.figureID.uuidString)
        #expect(args["p_part_id"] as? String == head.partID.uuidString)
        #expect(args["p_part_index"] as? Int == 0)
        #expect(args["p_drawing_media_asset_id"] as? String == Fixture.drawingAssetID.uuidString)
        #expect(args["p_strip_media_asset_id"] as? String == Fixture.stripAssetID.uuidString)
        #expect(args["p_idea_id"] as? String == "idea-a-grandma")
        #expect(args["p_client_operation_id"] as? String == operation.id.uuidString)
        #expect(args["p_client_id"] as? String == operation.clientID.uuidString)
        #expect(args["p_client_sequence"] as? Int == 42)
        #expect(args["p_local_created_at"] is String)
    }

    @Test func theLegsLeaveOutTheStripAndAMissingIdea() async throws {
        let recorder = CorpseRequestRecorder()
        CorpseStubURLProtocol.handler = { request in
            recorder.record(request)
            return Data(Self.submitAnswer.utf8)
        }
        let legs = Fixture.queuedPart(figure: 2, partIndex: 2)

        _ = try await Self.makeGateway().submitExquisiteCorpsePart(
            legs,
            drawingAssetID: Fixture.drawingAssetID,
            stripAssetID: nil,
            operation: operation
        )

        let body = try Self.body(of: #require(recorder.last))
        let args = try #require(body["args"] as? [String: Any])
        #expect(args["p_part_index"] as? Int == 2)
        #expect(args["p_strip_media_asset_id"] == nil)
        #expect(args["p_idea_id"] == nil)
    }

    // MARK: The rest

    @Test func ensuringTheGameReadsItsId() async throws {
        let recorder = CorpseRequestRecorder()
        CorpseStubURLProtocol.handler = { request in
            recorder.record(request)
            return Data(Self.ensureAnswer.utf8)
        }

        let result = try await Self.makeGateway().ensureExquisiteCorpseGame()

        #expect(result.gameID == Fixture.gameID)
        #expect(result.created)
        let body = try Self.body(of: #require(recorder.last))
        #expect(body["path"] as? String == "exquisiteCorpse:ensure_exquisite_corpse_game")
    }

    @Test func theStateIsAQueryOfTheScreensFunction() async throws {
        let recorder = CorpseRequestRecorder()
        CorpseStubURLProtocol.handler = { request in
            recorder.record(request)
            return Data(Self.stateAnswer.utf8)
        }

        let state = try await Self.makeGateway().loadExquisiteCorpse()

        #expect(state.userID == Fixture.me)
        #expect(state.game == nil)
        let request = try #require(recorder.last)
        #expect(request.url?.path == "/api/query")
        let body = try Self.body(of: request)
        #expect(body["path"] as? String == "exquisiteCorpse:get_exquisite_corpse")
    }

    @Test func theRevealSeenMarkNamesTheFigure() async throws {
        let recorder = CorpseRequestRecorder()
        CorpseStubURLProtocol.handler = { request in
            recorder.record(request)
            return Data(Self.revealSeenAnswer.utf8)
        }
        let figureID = try #require(UUID(uuidString: "55555555-5555-4555-8555-555555555555"))

        let result = try await Self.makeGateway().markExquisiteCorpseRevealSeen(figureID: figureID)

        #expect(result.figureID == figureID)
        let body = try Self.body(of: #require(recorder.last))
        #expect(body["path"] as? String == "exquisiteCorpse:mark_exquisite_corpse_reveal_seen")
        #expect((body["args"] as? [String: Any])?["p_figure_id"] as? String == figureID.uuidString)
    }

    @Test func aStarSendsTheValueItIsGiven() async throws {
        let recorder = CorpseRequestRecorder()
        CorpseStubURLProtocol.handler = { request in
            recorder.record(request)
            return Data(Self.starAnswer.utf8)
        }
        let figureID = try #require(UUID(uuidString: "55555555-5555-4555-8555-555555555555"))

        let result = try await Self.makeGateway().setExquisiteCorpseStar(figureID: figureID, starred: false)

        #expect(!result.starred)
        let body = try Self.body(of: #require(recorder.last))
        #expect(body["path"] as? String == "exquisiteCorpse:set_exquisite_corpse_star")
        let args = try #require(body["args"] as? [String: Any])
        #expect(args["p_figure_id"] as? String == figureID.uuidString)
        #expect(args["p_starred"] as? Bool == false)
    }

    @Test func theFirstPageOfTheHistoryLeavesOutTheCursor() async throws {
        let recorder = CorpseRequestRecorder()
        CorpseStubURLProtocol.handler = { request in
            recorder.record(request)
            return Data(#"{"status":"success","value":{"figures":[],"next_before_figure_number":null}}"#.utf8)
        }

        let page = try await Self.makeGateway().loadExquisiteCorpseHistory(
            starredOnly: false,
            beforeFigureNumber: nil,
            limit: 30
        )

        #expect(page.figures.isEmpty)
        #expect(page.nextBeforeFigureNumber == nil)
        let request = try #require(recorder.last)
        #expect(request.url?.path == "/api/query")
        let body = try Self.body(of: request)
        #expect(body["path"] as? String == "exquisiteCorpse:get_exquisite_corpse_history")
        let args = try #require(body["args"] as? [String: Any])
        #expect(args["p_starred_only"] as? Bool == false)
        #expect(args["p_limit"] as? Int == 30)
        #expect(args["p_before_figure_number"] == nil)
    }

    @Test func aLaterPageSendsTheCursorAndTheStarredFilter() async throws {
        let recorder = CorpseRequestRecorder()
        CorpseStubURLProtocol.handler = { request in
            recorder.record(request)
            return Data(#"{"status":"success","value":{"figures":[],"next_before_figure_number":4}}"#.utf8)
        }

        let page = try await Self.makeGateway().loadExquisiteCorpseHistory(
            starredOnly: true,
            beforeFigureNumber: 9,
            limit: 30
        )

        #expect(page.nextBeforeFigureNumber == 4)
        let body = try Self.body(of: #require(recorder.last))
        let args = try #require(body["args"] as? [String: Any])
        #expect(args["p_starred_only"] as? Bool == true)
        #expect(args["p_before_figure_number"] as? Int == 9)
    }

    @Test func aRefusalReachesTheCallerWithItsCodeAndMessage() async {
        CorpseStubURLProtocol.handler = { _ in
            Data(Self.refusalAnswer.utf8)
        }
        let head = Fixture.queuedPart(figure: 2, partIndex: 0)

        let error = await corpseThrownError {
            try await Self.makeGateway().submitExquisiteCorpsePart(
                head,
                drawingAssetID: Fixture.drawingAssetID,
                stripAssetID: Fixture.stripAssetID,
                operation: operation
            )
        }

        #expect(error as? PaeoniaConvexError == .server(code: "42501", message: "it is not your turn"))
    }

    // MARK: Helpers

    private static let ensureAnswer = """
    {"status":"success","value":{"game_id":"44444444-4444-4444-8444-444444444444","created":true}}
    """

    private static let stateAnswer = """
    {"status":"success","value":{"user_id":"11111111-1111-4111-8111-111111111111","partner_user_id":null,\
    "couple_id":"33333333-3333-4333-8333-333333333333","game":null,"current_figure":null,\
    "recent_figures":[],"ideas":[]}}
    """

    private static let revealSeenAnswer = """
    {"status":"success","value":{"figure_id":"55555555-5555-4555-8555-555555555555",\
    "reveal_seen_at":"2026-10-13T10:00:00.123Z"}}
    """

    private static let starAnswer = """
    {"status":"success","value":{"figure_id":"55555555-5555-4555-8555-555555555555","starred":false}}
    """

    private static let refusalAnswer = """
    {"status":"error","errorMessage":"x","errorData":{"code":"42501","message":"it is not your turn"}}
    """

    private static let submitAnswer = """
    {"status":"success","value":{"figure_id":"55555555-5555-4555-8555-555555555555",\
    "part_id":"66666666-6666-4666-8666-666666666666","part_index":0,"figure_finished":false,\
    "created_at":"2026-10-13T10:00:00.123Z"}}
    """

    private static func makeGateway() -> LiveExquisiteCorpseGateway {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CorpseStubURLProtocol.self]
        let client = PaeoniaConvexClient(
            deploymentURL: URL(string: "https://convex.test") ?? URL(fileURLWithPath: "/"),
            session: URLSession(configuration: configuration),
            tokenProvider: { "token" }
        )
        return LiveExquisiteCorpseGateway(client: client)
    }

    private static func body(of request: URLRequest) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: request.corpseBodyData) as? [String: Any])
    }
}

private extension URLRequest {
    /// URLSession moves `httpBody` into a stream before it reaches a URLProtocol.
    var corpseBodyData: Data {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class CorpseRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    var last: URLRequest? {
        lock.withLock { requests.last }
    }

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }
}

// URLProtocol requires `class` members, so the static-over-class rule cannot apply here.
// swiftlint:disable static_over_final_class
private final class CorpseStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: handler(request))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
// swiftlint:enable static_over_final_class
