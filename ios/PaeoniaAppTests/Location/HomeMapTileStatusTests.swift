import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct HomeMapTileStatusTests {
    private let suite = "HomeMapTileStatusTests.\(UUID().uuidString)"

    @Test func outageSurvivesRelaunchAndLateMapCompletion() async throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let status = HomeMapTileStatus(defaults: defaults) { _ in throw URLError(.badServerResponse) }

        await status.mapDidNotLoad()
        let retryAfter = try #require(defaults.object(forKey: HomeMapTileStatus.retryAfterKey) as? Date)
        #expect(!status.showsMapHeader)

        let restored = HomeMapTileStatus(defaults: defaults) { _ in
            Issue.record("An outage must wait until its retry date before probing")
        }
        await restored.checkIfDue()
        status.mapLoaded()
        #expect(!restored.showsMapHeader)
        #expect(!status.showsMapHeader)
        #expect(defaults.object(forKey: HomeMapTileStatus.retryAfterKey) as? Date == retryAfter)
    }

    @Test func offlineKeepsHeaderAndDoesNotRememberAnOutage() async throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let status = HomeMapTileStatus(defaults: defaults) { _ in throw URLError(.notConnectedToInternet) }

        await status.mapDidNotLoad()

        #expect(status.tiles == .offline)
        #expect(status.showsMapHeader)
        #expect(defaults.object(forKey: HomeMapTileStatus.retryAfterKey) == nil)
    }

    @Test func recoveryRequiresAWorkingConnection() async throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Date.distantPast, forKey: HomeMapTileStatus.retryAfterKey)
        let offline = HomeMapTileStatus(defaults: defaults) { _ in throw URLError(.notConnectedToInternet) }

        await offline.checkIfDue()
        #expect(!offline.showsMapHeader)
        #expect(defaults.object(forKey: HomeMapTileStatus.retryAfterKey) != nil)

        let recovered = HomeMapTileStatus(defaults: defaults) { _ in }
        await recovered.checkIfDue()
        #expect(recovered.showsMapHeader)
        #expect(defaults.object(forKey: HomeMapTileStatus.retryAfterKey) == nil)
    }

    @Test func aStalledMapFallsBackEvenWhenTheServiceAnswers() async throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let status = HomeMapTileStatus(defaults: defaults) { _ in }

        await status.mapDidNotLoad()

        #expect(!status.showsMapHeader)
    }

    @Test func cancelledProbeDoesNotBecomeAnOutage() async throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let status = HomeMapTileStatus(defaults: defaults) { _ in throw URLError(.cancelled) }

        await status.mapDidNotLoad()

        #expect(status.tiles == .trying)
        #expect(defaults.object(forKey: HomeMapTileStatus.retryAfterKey) == nil)
    }

    @Test func freshMapCompletionWinsOverAnOlderProbe() async throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var onCheck: (() -> Void)?
        let status = HomeMapTileStatus(defaults: defaults) { _ in
            onCheck?()
            throw URLError(.badServerResponse)
        }
        status.mapLoaded()
        onCheck = { status.mapLoaded() }

        await status.mapDidNotLoad()
        onCheck = nil

        #expect(status.tiles == .available)
        #expect(defaults.object(forKey: HomeMapTileStatus.retryAfterKey) == nil)
    }

    @Test(arguments: [200, 503])
    func probeChecksTileDeliveryAfterSuccessfulMetadata(tileStatus: Int) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HomeMapProbeURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = try #require(URL(string: "https://map.invalid/style.json?status=\(tileStatus)"))

        do {
            try await HomeMapTileStatus.fetchStyle(url, session: session)
            #expect(tileStatus == 200)
        } catch {
            #expect(tileStatus == 503)
            #expect((error as? URLError)?.code == .badServerResponse)
        }
    }

}

private final class HomeMapProbeURLProtocol: URLProtocol, @unchecked Sendable {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let status = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "status" })?.value ?? "200"
        let body: Data
        var responseStatus = 200
        switch url.path {
        case "/style.json":
            body = Data("""
                {"sources":{
                    "ne2_shaded":{"type":"raster","tiles":["https://map.invalid/relief/{z}/{x}/{y}.png"]},
                    "openmaptiles":{"type":"vector","url":"https://map.invalid/source.json?status=\(status)"}
                }}
                """.utf8)
        case "/source.json":
            body = Data("""
                {"tiles":["https://map.invalid/tiles/{z}/{x}/{y}.pbf?status=\(status)"]}
                """.utf8)
        case "/tiles/0/0/0.pbf":
            responseStatus = Int(status) ?? 503
            body = Data([0x1A, 0x02, 0x28, 0x02])
        default:
            responseStatus = 404
            body = Data()
        }
        guard let response = HTTPURLResponse(
            url: url, statusCode: responseStatus, httpVersion: nil, headerFields: nil
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
