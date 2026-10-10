import Foundation
import Testing
@testable import PaeoniaApp

/// Runs the real upload services against a stubbed URL session to check the
/// reserve, upload, finalize order and that finalize receives the storage id.
struct MediaUploadFlowTests {
    private static let storageID = "kg2storage-id"

    @Test func memoryUploadReservesUploadsThenFinalizesWithStorageID() async throws {
        let stub = MediaUploadStub()
        let service = LiveMemoryMediaUploadService(client: try stub.makeClient(), isSignedIn: { true })
        let media = MemoryUploadMedia(
            data: Data([0x0A, 0x0B, 0x0C]),
            purpose: .photo,
            mimeType: "image/jpeg",
            fileExtension: "jpg"
        )

        let result = try await service.uploadMedia(
            media,
            memoryMediaID: UUID(),
            coupleID: UUID(),
            reserveOperation: Self.operation(sequence: 1),
            finalizeOperation: Self.operation(sequence: 2)
        )

        #expect(result.mediaAssetID == stub.mediaAssetID)
        #expect(stub.requestLabels == [
            "mutation media:create_pending_media_upload",
            "upload",
            "mutation media:finalize_media_upload"
        ])
        #expect(stub.uploadedBody == media.data)
        #expect(stub.uploadContentType == "image/jpeg")
        #expect(stub.finalizeArgs["p_storage_id"] as? String == Self.storageID)
        #expect(stub.finalizeArgs["p_media_asset_id"] as? String == stub.mediaAssetID.uuidString)
    }

    @Test func dailyAnswerUploadReservesUploadsThenFinalizesWithStorageID() async throws {
        let stub = MediaUploadStub()
        let service = LiveDailyAnswerMediaUploadService(client: try stub.makeClient())
        let media = DailyAnswerUploadMedia(
            data: Data([0x01, 0x02]),
            purpose: .voice,
            mimeType: "audio/mp4",
            fileExtension: "m4a",
            durationMs: 900
        )

        let assetID = try await service.uploadMedia(
            media,
            answerID: UUID(),
            coupleID: UUID(),
            reserveOperation: Self.operation(sequence: 1),
            finalizeOperation: Self.operation(sequence: 2)
        )

        #expect(assetID == stub.mediaAssetID)
        #expect(stub.requestLabels == [
            "mutation media:create_pending_media_upload",
            "upload",
            "mutation media:finalize_media_upload"
        ])
        #expect(stub.uploadContentType == "audio/mp4")
        #expect(stub.finalizeArgs["p_storage_id"] as? String == Self.storageID)
    }

    @Test func memoryUploadFailsLocallyWhenSignedOut() async throws {
        let stub = MediaUploadStub()
        let service = LiveMemoryMediaUploadService(client: try stub.makeClient(), isSignedIn: { false })
        let media = MemoryUploadMedia(
            data: Data([0x01]),
            purpose: .photo,
            mimeType: "image/jpeg",
            fileExtension: "jpg"
        )

        await #expect(throws: PaeoniaConvexError.notAuthenticated) {
            _ = try await service.uploadMedia(
                media,
                memoryMediaID: UUID(),
                coupleID: UUID(),
                reserveOperation: Self.operation(sequence: 1),
                finalizeOperation: Self.operation(sequence: 2)
            )
        }
        #expect(stub.requestLabels.isEmpty)
    }

    @Test func signedMediaURLReadsSignedURLFromFirstRow() async throws {
        let stub = MediaUploadStub()
        let assetID = UUID()

        let url = try await stub.makeClient().signedMediaURL(for: assetID, expiresInSeconds: 3_600)

        #expect(url == URL(string: "https://media.paeonia.test/media?asset=1&exp=2&sig=3"))
        #expect(stub.requestLabels == ["mutation media:get_media_signed_url"])
    }

    private static func operation(sequence: Int64) -> SyncClientOperation {
        SyncClientOperation(
            id: UUID(),
            clientID: UUID(),
            clientSequence: sequence,
            localCreatedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }
}

/// A stubbed backend. Each instance gets its own host, so parallel tests do not
/// share recorded requests.
private final class MediaUploadStub: @unchecked Sendable {
    let mediaAssetID = UUID()
    let host = "stub-\(UUID().uuidString.lowercased()).test"
    private let lock = NSLock()
    private var labels: [String] = []
    private var uploaded: Data?
    private var uploadType: String?
    private var finalize: [String: Any] = [:]

    func makeClient() throws -> PaeoniaConvexClient {
        let baseURL = try #require(URL(string: "https://\(host)"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.register(host: host) { [self] request in respond(to: request) }
        return PaeoniaConvexClient(
            deploymentURL: baseURL,
            session: URLSession(configuration: configuration),
            tokenProvider: { "token" }
        )
    }

    var requestLabels: [String] { lock.withLock { labels } }
    var uploadedBody: Data? { lock.withLock { uploaded } }
    var uploadContentType: String? { lock.withLock { uploadType } }
    var finalizeArgs: [String: Any] { lock.withLock { finalize } }

    private func respond(to request: StubRequest) -> Data {
        if request.path.hasPrefix("/upload") {
            lock.withLock {
                labels.append("upload")
                uploaded = request.body
                uploadType = request.contentType
            }
            return Data(#"{"storageId":"kg2storage-id"}"#.utf8)
        }

        let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        let path = body["path"] as? String ?? ""
        let args = body["args"] as? [String: Any] ?? [:]
        lock.withLock { labels.append("mutation \(path)") }

        let value: String
        switch path {
        case "media:create_pending_media_upload":
            value = """
            [{"media_asset_id":"\(mediaAssetID.uuidString)","bucket":"couple-media",
            "storage_path":"couple/asset.bin","upload_url":"https://\(host)/upload/abc"}]
            """
        case "media:finalize_media_upload":
            lock.withLock { finalize = args }
            value = #"[{"media_asset_id":"\#(mediaAssetID.uuidString)","upload_status":"finalized"}]"#
        default:
            value = #"[{"signed_url":"https://media.paeonia.test/media?asset=1&exp=2&sig=3"}]"#
        }
        return Data(#"{"status":"success","value":\#(value)}"#.utf8)
    }
}

private struct StubRequest {
    let path: String
    let contentType: String?
    let body: Data
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: @Sendable (StubRequest) -> Data] = [:]

    static func register(host: String, handler: @escaping @Sendable (StubRequest) -> Data) {
        lock.withLock { handlers[host] = handler }
    }

    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        guard let url = request.url,
              let host = url.host(),
              let handler = Self.lock.withLock({ Self.handlers[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }

        let stubRequest = StubRequest(
            path: url.path(),
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            body: Self.readBody(of: request)
        )
        let data = handler(stubRequest)
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
