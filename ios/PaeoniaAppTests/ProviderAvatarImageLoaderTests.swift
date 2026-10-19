import Foundation
import Testing
@testable import PaeoniaApp

struct ProviderAvatarImageLoaderTests {
    @Test func redirectWithinTheOriginalHostIsFollowed() async throws {
        let original = try #require(URL(string: "https://lh3.googleusercontent.com/avatar"))
        let next = try #require(URL(string: "https://lh3.googleusercontent.com/avatar-2"))

        let followed = try await redirectTarget(from: original, to: next)

        #expect(followed?.url == next)
    }

    @Test func redirectToAnotherHostIsStoppedBeforeTheRequestIsSent() async throws {
        let original = try #require(URL(string: "https://lh3.googleusercontent.com/avatar"))
        let other = try #require(URL(string: "https://example.com/avatar"))

        let followed = try await redirectTarget(from: original, to: other)

        #expect(followed == nil)
    }

    @Test func redirectDowngradingToHTTPIsStopped() async throws {
        let original = try #require(URL(string: "https://lh3.googleusercontent.com/avatar"))
        let insecure = try #require(URL(string: "http://lh3.googleusercontent.com/avatar"))

        let followed = try await redirectTarget(from: original, to: insecure)

        #expect(followed == nil)
    }

    @Test func loaderRejectsAnUnknownLengthBodyOverTheByteBudget() async throws {
        let host = "avatar-large.test"
        AvatarStubURLProtocol.register(
            host: host,
            statusCode: 200,
            headers: ["Content-Type": "image/png"],
            body: Data(count: HTTPSProviderAvatarImageLoader.maximumByteCount + 1)
        )
        let loader = makeLoader()

        let data = await loader.imageData(from: try #require(URL(string: "https://\(host)/avatar")))

        #expect(data == nil)
    }

    @Test func loaderRejectsFailedStatusCodesAndNonImageTypes() async throws {
        let failedHost = "avatar-missing.test"
        AvatarStubURLProtocol.register(
            host: failedHost,
            statusCode: 404,
            headers: ["Content-Type": "image/png"],
            body: Data([0x01])
        )
        let htmlHost = "avatar-html.test"
        AvatarStubURLProtocol.register(
            host: htmlHost,
            statusCode: 200,
            headers: ["Content-Type": "text/html"],
            body: Data("<html></html>".utf8)
        )
        let loader = makeLoader()

        let failed = await loader.imageData(from: try #require(URL(string: "https://\(failedHost)/avatar")))
        let html = await loader.imageData(from: try #require(URL(string: "https://\(htmlHost)/avatar")))

        #expect(failed == nil)
        #expect(html == nil)
    }

    private func makeLoader() -> HTTPSProviderAvatarImageLoader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AvatarStubURLProtocol.self]
        return HTTPSProviderAvatarImageLoader(session: URLSession(configuration: configuration))
    }

    /// Asks the redirect guard what to do with a redirect, without any network.
    private func redirectTarget(from original: URL, to next: URL) async throws -> URLRequest? {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: original)
        let response = try #require(
            HTTPURLResponse(
                url: original,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": next.absoluteString]
            )
        )

        let guardDelegate = ProviderAvatarRedirectGuard(originalURL: original)
        return await withCheckedContinuation { continuation in
            guardDelegate.urlSession(
                session,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: next)
            ) { continuation.resume(returning: $0) }
        }
    }
}

private final class AvatarStubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Stub {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]

    static func register(host: String, statusCode: Int, headers: [String: String], body: Data) {
        lock.withLock {
            stubs[host] = Stub(statusCode: statusCode, headers: headers, body: body)
        }
    }

    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        guard let url = request.url,
              let host = url.host(),
              let stub = Self.lock.withLock({ Self.stubs[host] }),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: stub.statusCode,
                  httpVersion: nil,
                  headerFields: stub.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
