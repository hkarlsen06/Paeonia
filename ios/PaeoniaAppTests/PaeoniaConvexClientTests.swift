import Foundation
import Testing
@testable import PaeoniaApp

/// The stub keeps one shared handler, so these tests run one at a time.
@Suite(.serialized)
struct PaeoniaConvexClientTests {
    private struct EchoArgs: Encodable {
        let userID: UUID
        let note: String?

        enum CodingKeys: String, CodingKey {
            case userID = "p_user_id"
            case note = "p_note"
        }
    }

    private struct Row: Decodable, Equatable {
        let name: String
    }

    @Test func mutationSendsPathArgsAndBearerToken() async throws {
        let userID = try #require(UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789"))
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.record(request)
            return (200, Data(#"{"status":"success","value":[{"name":"Alex"}]}"#.utf8))
        }
        let client = Self.makeClient(token: "clerk-token")

        let rows: [Row] = try await client.mutation(
            "identity:get_thing",
            args: EchoArgs(userID: userID, note: nil)
        )

        #expect(rows == [Row(name: "Alex")])
        let request = try #require(recorder.last)
        #expect(request.url?.path == "/api/mutation")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer clerk-token")
        let body = try #require(try JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any])
        #expect(body["path"] as? String == "identity:get_thing")
        #expect(body["format"] as? String == "json")
        let args = try #require(body["args"] as? [String: Any])
        // The client must not change the spelling of ids. The backend lowercases them.
        #expect(args["p_user_id"] as? String == "ABCDEF01-2345-6789-ABCD-EF0123456789")
        #expect(args["p_note"] == nil)
    }

    @Test func queryMapsFunctionErrorsToServerErrors() async {
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"status":"error","errorMessage":"no","errorData":{"code":"42501","message":"denied"}}"#.utf8))
        }
        let client = Self.makeClient()

        await #expect(throws: PaeoniaConvexError.server(code: "42501", message: "denied")) {
            let _: Row = try await client.query("identity:get_thing")
        }
    }

    @Test func requestWithoutTokenOmitsAuthorizationHeader() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.record(request)
            return (200, Data(#"{"status":"success","value":null}"#.utf8))
        }
        let client = Self.makeClient(token: nil)

        try await client.mutation("identity:ping")

        #expect(recorder.last?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func nullValueDecodesIntoOptionalAndIgnoredResults() async throws {
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"status":"success","value":null}"#.utf8))
        }
        let client = Self.makeClient()

        let optionalRow: Row? = try await client.mutation("identity:maybe")
        try await client.mutation("identity:void")

        #expect(optionalRow == nil)
    }

    @Test func nullValueFailsForNonOptionalResult() async {
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"status":"success","value":null}"#.utf8))
        }
        let client = Self.makeClient()

        await #expect(throws: DecodingError.self) {
            let _: Row = try await client.mutation("identity:required")
        }
    }

    @Test func firstRowAcceptsObjectArrayAndNull() throws {
        let decoder = JSONDecoder()

        let object = try decoder.decode(FirstRow<Row>.self, from: Data(#"{"name":"A"}"#.utf8))
        let array = try decoder.decode(FirstRow<Row>.self, from: Data(#"[{"name":"B"},{"name":"C"}]"#.utf8))
        let empty = try decoder.decode(FirstRow<Row>.self, from: Data("[]".utf8))
        let null = try decoder.decode(FirstRow<Row>.self, from: Data("null".utf8))

        #expect(object.row == Row(name: "A"))
        #expect(array.row == Row(name: "B"))
        #expect(empty.row == nil)
        #expect(null.row == nil)
    }

    @Test func datesUseMillisecondISOStringsInBothDirections() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.record(request)
            return (200, Data(#"{"status":"success","value":"2026-07-01T12:30:45.123Z"}"#.utf8))
        }
        let client = Self.makeClient()
        let sent = Date(timeIntervalSince1970: 1_782_909_045.123)

        let received: Date = try await client.mutation("identity:echo", args: ["p_at": sent])

        let request = try #require(recorder.last)
        let body = try #require(try JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any])
        let args = try #require(body["args"] as? [String: Any])
        #expect(args["p_at"] as? String == "2026-07-01T12:30:45.123Z")
        #expect(abs(received.timeIntervalSince1970 - 1_782_909_045.123) < 0.001)
    }

    @Test func errorEnvelopeKeepsBackendCodeAndMessage() async {
        StubURLProtocol.handler = { _ in
            (
                560,
                Data(
                    """
                    {"status":"error","errorMessage":"[Request ID: x] Server Error",\
                    "errorData":{"code":"40001","message":"revision conflict"}}
                    """.utf8
                )
            )
        }
        let client = Self.makeClient()

        do {
            try await client.mutation("widget:submit")
            Issue.record("Expected a server error")
        } catch let error as PaeoniaConvexError {
            #expect(error == .server(code: "40001", message: "revision conflict"))
            // Existing substring checks read `String(describing:)`.
            #expect(String(describing: error).contains("revision conflict"))
            #expect(String(describing: error).contains("40001"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func errorEnvelopeWithoutErrorDataFallsBackToErrorMessage() async {
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"status":"error","errorMessage":"Something broke"}"#.utf8))
        }
        let client = Self.makeClient()

        await #expect(throws: PaeoniaConvexError.server(code: nil, message: "Something broke")) {
            try await client.mutation("identity:broken")
        }
    }

    @Test func unauthorizedWithoutEnvelopeMeansNotAuthenticated() async {
        StubURLProtocol.handler = { _ in (401, Data("Unauthorized".utf8)) }
        let client = Self.makeClient()

        await #expect(throws: PaeoniaConvexError.notAuthenticated) {
            try await client.mutation("identity:ping")
        }
    }

    @Test func otherHTTPFailuresReportStatusAndBody() async {
        StubURLProtocol.handler = { _ in (502, Data("Bad gateway".utf8)) }
        let client = Self.makeClient()

        await #expect(throws: PaeoniaConvexError.http(status: 502, body: "Bad gateway")) {
            try await client.mutation("identity:ping")
        }
    }

    @Test func tokenProviderFailureStopsTheRequestBeforeItIsSent() async {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.record(request)
            return (200, Data(#"{"status":"success","value":null}"#.utf8))
        }
        let client = PaeoniaConvexClient(
            deploymentURL: Self.baseURL,
            session: Self.makeSession(),
            tokenProvider: { throw PaeoniaConvexError.notAuthenticated }
        )

        await #expect(throws: PaeoniaConvexError.notAuthenticated) {
            try await client.mutation("identity:ping")
        }
        #expect(recorder.last == nil)
    }

    @Test func signOutDisablesTheDeviceThatRegistrationReturned() async throws {
        let suiteName = "PaeoniaConvexClientTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let deviceID = "0F0F0F0F-0000-4000-8000-000000000001"
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.record(request)
            let body = (try? JSONSerialization.jsonObject(with: request.bodyData)) as? [String: Any]
            if body?["path"] as? String == "identity:register_user_device" {
                return (200, Data(#"{"status":"success","value":"\#(deviceID)"}"#.utf8))
            }
            return (200, Data(#"{"status":"success","value":true}"#.utf8))
        }
        let client = Self.makeClient()
        let store = PushRegistrationFingerprintStore(channel: .device, defaults: defaults)
        let registration = ConvexPushRegistrationService(
            client: client,
            currentAccountID: { "user_a" },
            fingerprintStore: store
        )

        await registration.registerDevice(pushToken: String(repeating: "ab", count: 32))
        await ConvexPushRegistrationService.disableRegisteredDevice(client: client, fingerprintStore: store)

        let request = try #require(recorder.last)
        let body = try #require(try JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any])
        #expect(body["path"] as? String == "identity:disable_user_device")
        #expect((body["args"] as? [String: Any])?["p_device_id"] as? String == deviceID)
        // The next sign-in registers the phone again.
        #expect(store.lastSent() == nil)
    }

    private static let baseURL = URL(string: "https://convex.test") ?? URL(fileURLWithPath: "/")

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func makeClient(token: String? = "token") -> PaeoniaConvexClient {
        PaeoniaConvexClient(
            deploymentURL: baseURL,
            session: makeSession(),
            tokenProvider: { token }
        )
    }
}

// In an extension so the suite's struct stays a readable length. The tests still
// run one at a time with the rest of the suite, because they share the stub.
extension PaeoniaConvexClientTests {
    @Test func onlySucceededWritesReachTheWriteObserver() async throws {
        let paths = PathRecorder()
        PaeoniaConvexClient.setWriteObserver { paths.record($0) }
        StubURLProtocol.handler = { request in
            let body = (try? JSONSerialization.jsonObject(with: request.bodyData)) as? [String: Any]
            if body?["path"] as? String == "observerTest:failing_write" {
                return (200, Data(#"{"status":"error","errorMessage":"no"}"#.utf8))
            }
            return (200, Data(#"{"status":"success","value":null}"#.utf8))
        }
        let client = Self.makeClient()

        try await client.mutation("observerTest:write")
        try await client.query("observerTest:read")
        await #expect(throws: PaeoniaConvexError.self) {
            try await client.mutation("observerTest:failing_write")
        }
        let _: PaeoniaConvexIgnoredResult = try await client.action("observerTest:action")

        // Other suites may send their own writes meanwhile, so only this test's paths count.
        #expect(paths.all.filter { $0.hasPrefix("observerTest:") } == ["observerTest:write", "observerTest:action"])
    }
}

private extension URLRequest {
    /// URLSession moves `httpBody` into a stream before it reaches a URLProtocol.
    var bodyData: Data {
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

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    var last: URLRequest? {
        lock.withLock { requests.last }
    }

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }
}

private final class PathRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    var all: [String] {
        lock.withLock { paths }
    }

    func record(_ path: String) {
        lock.withLock { paths.append(path) }
    }
}

// URLProtocol requires `class` members, so the static-over-class rule cannot apply here.
// swiftlint:disable static_over_final_class
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
// swiftlint:enable static_over_final_class
