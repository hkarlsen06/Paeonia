import CoreLocation
import Foundation
import MapLibre
import Testing
import UIKit
import XCTest
@testable import PaeoniaApp

@MainActor
struct HomeMapTileStatusTests {
    @Test func failedProbeFallsBackButDoesNotDisableTheNextLaunch() async {
        let status = HomeMapTileStatus { _ in throw URLError(.badServerResponse) }
        await status.mapDidNotLoad()
        #expect(!status.showsMapHeader)

        let relaunched = HomeMapTileStatus { _ in }
        #expect(relaunched.showsMapHeader)
        await relaunched.mapDidNotLoad()
        #expect(relaunched.tiles == .available)
    }

    @Test func lateMapCompletionRecoversFromFailedProbe() async {
        let status = HomeMapTileStatus { _ in throw URLError(.badServerResponse) }
        await status.mapDidNotLoad()
        #expect(!status.showsMapHeader)

        status.mapLoaded()

        #expect(status.tiles == .available)
        #expect(status.showsMapHeader)
    }

    @Test func returningToAppRechecksBeforeRetryDate() async {
        var serviceWorks = false
        let status = HomeMapTileStatus { _ in
            if !serviceWorks { throw URLError(.badServerResponse) }
        }
        await status.mapDidNotLoad()
        #expect(!status.showsMapHeader)
        serviceWorks = true
        await status.checkOnReturn()
        #expect(status.tiles == .available)
    }

    @Test func automaticChecksWaitBetweenEndpointFailures() async throws {
        var checks = 0
        let status = HomeMapTileStatus { _ in
            checks += 1
            throw URLError(.badServerResponse)
        }
        await status.mapDidNotLoad()
        await status.checkIfDue()
        #expect(checks == 1)
        guard case let .unavailable(retryAfter) = status.tiles else {
            Issue.record("Failed endpoint must show the fallback")
            return
        }
        #expect(retryAfter > .now)
        #expect(retryAfter.timeIntervalSinceNow <= 60)
    }

    @Test func cancelledRecoveryCanRetryOnNextReturn() async {
        var checks = 0
        let status = HomeMapTileStatus { _ in
            checks += 1
            if checks == 1 { throw URLError(.badServerResponse) }
            if checks == 2 { throw CancellationError() }
        }
        await status.mapDidNotLoad()
        await status.checkOnReturn()
        #expect(!status.showsMapHeader)
        await status.checkOnReturn()
        #expect(status.tiles == .available)
    }

    @Test func offlineKeepsHeaderAndRecoversWhenConnectionReturns() async {
        var isOffline = true
        let status = HomeMapTileStatus { _ in
            if isOffline { throw URLError(.notConnectedToInternet) }
        }
        await status.mapDidNotLoad()
        #expect(status.tiles == .offline)
        #expect(status.showsMapHeader)
        isOffline = false
        await status.checkOnReturn()
        #expect(status.tiles == .available)
    }

    @Test func offlineProbeCannotClearAnEndpointFailure() async {
        var isOffline = false
        let status = HomeMapTileStatus { _ in
            throw URLError(isOffline ? .notConnectedToInternet : .badServerResponse)
        }
        await status.mapDidNotLoad()
        isOffline = true
        await status.checkOnReturn()
        #expect(!status.showsMapHeader)
    }

    @Test func slowRenderKeepsMapWhenEndpointsAnswer() async {
        let status = HomeMapTileStatus { _ in }
        await status.mapDidNotLoad()
        #expect(status.tiles == .available)
        #expect(status.showsMapHeader)
        // A repeated timeout must also leave a reachable map alone.
        await status.mapDidNotLoad()
        #expect(status.showsMapHeader)
    }

    @Test func cancelledProbeDoesNotBecomeAnOutage() async {
        let status = HomeMapTileStatus { _ in throw URLError(.cancelled) }
        await status.mapDidNotLoad()
        #expect(status.tiles == .trying)
        #expect(status.showsMapHeader)
    }

    @Test func freshMapCompletionWinsOverAnOlderProbe() async {
        var onCheck: (() -> Void)?
        let status = HomeMapTileStatus { _ in
            onCheck?()
            throw URLError(.badServerResponse)
        }
        onCheck = { status.mapLoaded() }
        await status.mapDidNotLoad()
        onCheck = nil
        #expect(status.tiles == .available)
    }

    @Test(arguments: [false, true])
    func repeatedDelegateFailureWaitsForCancelledProbeBeforeRetrying(afterBackgrounding: Bool) async throws {
        let started = XCTestExpectation(description: "First endpoint check started")
        var finishFirst: CheckedContinuation<Void, Never>?
        var checks = 0
        let status = HomeMapTileStatus { _ in
            checks += 1
            if checks == 1 {
                await withCheckedContinuation { continuation in
                    finishFirst = continuation
                    started.fulfill()
                }
                throw CancellationError()
            }
        }
        let coordinator = HomeMapLibreView.Coordinator()
        let map = MLNMapView(frame: .zero, styleURL: HomeMapLibreView.styleURL)
        coordinator.parent = HomeMapLibreView(
            current: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            partner: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            isNear: false, framedBox: .zero, avatarSize: 60, tiles: status, onProjection: { _ in }
        )
        defer {
            finishFirst?.resume()
            coordinator.stopWatchingLoad()
        }
        coordinator.mapViewDidFailLoadingMap(map, withError: URLError(.timedOut))
        let result = await XCTWaiter.fulfillment(of: [started], timeout: 3)
        try #require(result == .completed)

        if afterBackgrounding {
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        }
        coordinator.mapViewDidFailLoadingMap(map, withError: URLError(.timedOut))
        // Let the replacement run while cancellation of the first request is still pending.
        await Task.yield()
        finishFirst?.resume()
        finishFirst = nil
        await coordinator.loadTask?.value

        #expect(checks == 2)
        #expect(status.tiles == .available)
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
