import Foundation
import Synchronization
import Testing
@testable import PaeoniaApp

/// Posters download two at a time. A video someone opened to watch never waits for them.
struct VideoFileCacheDownloadTurnTests {
    @Test func aVideoOpenedToWatchStartsWhileTwoPostersDownload() async throws {
        try await withHeldServer { cache, server in
            for _ in 0..<2 {
                Task { _ = try? await cache.fileURL(for: UUID()) }
            }
            try await server.waitForRequests(2)

            Task { _ = try? await cache.fileURL(for: UUID(), priority: .playback) }

            try await server.waitForRequests(3)
        }
    }

    @Test func aWaitingPosterOpenedToWatchStartsAtOnce() async throws {
        try await withHeldServer { cache, server in
            let waiting = UUID()
            for _ in 0..<2 {
                Task { _ = try? await cache.fileURL(for: UUID()) }
            }
            try await server.waitForRequests(2)
            Task { _ = try? await cache.fileURL(for: waiting) }
            try await Task.sleep(for: .milliseconds(200))
            #expect(server.requests == 2, "a third poster waits for a turn")

            Task { _ = try? await cache.fileURL(for: waiting, priority: .playback) }

            try await server.waitForRequests(3)
        }
    }

    private func withHeldServer(_ body: (VideoFileCache, HeldMediaServer) async throws -> Void) async throws {
        let server = HeldMediaServer()
        defer { server.release() }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoFileCacheDownloadTurnTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(VideoFileCache(client: try server.client(), directoryURL: directory), server)
    }
}

/// Holds every signed URL request until `release`, then fails it, and counts them, so a
/// test sees how many downloads have started.
private final class HeldMediaServer: Sendable {
    private let host = "held-video-\(UUID().uuidString.lowercased()).invalid"

    init() {
        HeldMediaProtocol.state.withLock { $0[host] = .init() }
    }

    var requests: Int {
        HeldMediaProtocol.state.withLock { $0[host]?.requests ?? 0 }
    }

    func client() throws -> PaeoniaConvexClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldMediaProtocol.self]
        return PaeoniaConvexClient(
            deploymentURL: try #require(URL(string: "https://\(host)")),
            session: URLSession(configuration: configuration),
            tokenProvider: { nil }
        )
    }

    func waitForRequests(_ count: Int) async throws {
        for _ in 0..<500 where requests < count {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(requests == count)
    }

    func release() {
        HeldMediaProtocol.state.withLock { state in
            for _ in 0..<16 { state[host]?.gate.signal() }
        }
    }
}

// swiftlint:disable static_over_final_class
private final class HeldMediaProtocol: URLProtocol, @unchecked Sendable {
    struct Held {
        let gate = DispatchSemaphore(value: 0)
        var requests = 0
    }

    static let state = Mutex<[String: Held]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let gate = request.url?.host().flatMap { host in
            Self.state.withLock { state -> DispatchSemaphore? in
                state[host]?.requests += 1
                return state[host]?.gate
            }
        }
        // Waits off the loading thread, which the session's other requests share.
        DispatchQueue.global().async {
            _ = gate?.wait(timeout: .now() + 10)
            self.client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }

    override func stopLoading() {}
}
// swiftlint:enable static_over_final_class
