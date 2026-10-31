import Foundation
import Observation

/// Whether OpenFreeMap can draw Home's map. OpenFreeMap promises no uptime, so while it is
/// down Home shows the couple on the map card (`CoupleMapCard`) instead.
nonisolated enum HomeMapTiles: Equatable, Sendable {
    /// Nothing is known yet. Home shows the map header.
    case trying
    case available
    /// The phone has no connection. The map header stays, since the map returns with the connection.
    case offline
    /// OpenFreeMap failed while the phone was online. Home shows the map card until a check
    /// from `retryAfter` on gets an answer.
    case unavailable(retryAfter: Date)
}

/// Works out `HomeMapTiles` from what the map reports and from quiet checks of OpenFreeMap.
/// It remembers an outage across launches, so Home opens in the layout it will keep.
@Observable
final class HomeMapTileStatus {
    private(set) var tiles: HomeMapTiles
    let styleURL: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let check: (URL) async throws -> Void
    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private var loadRevision = 0

    /// How long the map may take to draw before Home checks whether OpenFreeMap answers.
    static let loadTimeout: Duration = .seconds(10)
    /// An outage usually lasts a while. Waiting this long before showing the map header again
    /// keeps Home from switching layouts back and forth.
    private static let retryDelay: TimeInterval = 3 * 60 * 60
    static let retryAfterKey = "home.mapTiles.retryAfter"

    init(
        styleURL: URL = HomeMapLibreView.styleURL,
        defaults: UserDefaults = .standard,
        check: @escaping (URL) async throws -> Void = { try await HomeMapTileStatus.fetchStyle($0) }
    ) {
        self.styleURL = styleURL
        self.defaults = defaults
        self.check = check
        tiles = (defaults.object(forKey: Self.retryAfterKey) as? Date)
            .map { .unavailable(retryAfter: $0) } ?? .trying
    }

    /// False while OpenFreeMap is down, so Home shows the map card instead of the map header.
    var showsMapHeader: Bool {
        if case .unavailable = tiles { false } else { true }
    }

    func mapLoaded() {
        guard showsMapHeader else { return }
        loadRevision += 1
        update(.available)
    }

    /// The map failed to load or took too long. Finds out whether the phone is offline or
    /// OpenFreeMap is down.
    func mapDidNotLoad() async {
        guard showsMapHeader else { return }
        await checkTiles(mapDidNotLoad: true)
    }

    /// Checks right away when the person comes back to the app and the map could be back.
    func checkIfDue() async {
        switch tiles {
        case .offline:
            await checkTiles()
        case let .unavailable(retryAfter) where retryAfter <= .now:
            await checkTiles()
        default:
            break
        }
    }

    /// While Home is on screen, checks every half minute while offline, and every few minutes
    /// from `retryAfter` on while OpenFreeMap is down. Returns when the map works again.
    func watch() async {
        var hasChecked = false
        while let delay = nextCheck(afterCheck: hasChecked) {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await checkTiles()
            hasChecked = true
        }
    }

    private func nextCheck(afterCheck: Bool) -> Duration? {
        switch tiles {
        case .trying, .available:
            return nil
        case .offline:
            return .seconds(30)
        case let .unavailable(retryAfter):
            let untilRetry = retryAfter.timeIntervalSinceNow
            if untilRetry > 0 { return .seconds(untilRetry) }
            return afterCheck ? .seconds(5 * 60) : .zero
        }
    }

    private func checkTiles(mapDidNotLoad: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let before = tiles
        let revision = loadRevision
        let failure: PaeoniaFailure?
        do {
            try await check(styleURL)
            failure = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            failure = PaeoniaFailure(error)
        }
        // The map may have loaded meanwhile, and a cancelled check says nothing about OpenFreeMap.
        guard tiles == before, loadRevision == revision, !Task.isCancelled else { return }
        applyProbeResult(failure, mapDidNotLoad: mapDidNotLoad)
    }

    private func applyProbeResult(_ failure: PaeoniaFailure?, mapDidNotLoad: Bool) {
        switch (failure, tiles) {
        case (nil, _) where mapDidNotLoad:
            // Reachable endpoints do not mean the map drew. Keep a stalled map off Home.
            update(.unavailable(retryAfter: .now.addingTimeInterval(Self.retryDelay)))
        case (nil, _):
            update(.available)
        case (.offline, .unavailable):
            // No connection says nothing about OpenFreeMap. Keep the map card until a check gets an answer.
            break
        case (.offline, _):
            update(.offline)
        case (.other, .unavailable):
            // Still down. Keep the first `retryAfter`, so checks go on every few minutes.
            break
        case (.other, _):
            update(.unavailable(retryAfter: .now.addingTimeInterval(Self.retryDelay)))
        }
    }

    private func update(_ next: HomeMapTiles) {
        guard tiles != next else { return }
        tiles = next
        switch next {
        case .available:
            defaults.removeObject(forKey: Self.retryAfterKey)
        case let .unavailable(retryAfter):
            defaults.set(retryAfter, forKey: Self.retryAfterKey)
        case .trying, .offline:
            break
        }
    }
}

extension HomeMapTileStatus {
    /// Checks a world tile too. The style and its source description can work while
    /// OpenFreeMap's tile server is down.
    nonisolated static func fetchStyle(_ url: URL, session: URLSession = .shared) async throws {
        let style = try await JSONDecoder().decode(Style.self, from: fetch(url, session: session))
        for source in style.sources.values where source.type == "vector" {
            guard let sourceURL = source.url else { throw URLError(.badServerResponse) }
            let tileJSON = try await JSONDecoder().decode(TileJSON.self, from: fetch(sourceURL, session: session))
            guard let template = tileJSON.tiles.first,
                  let tileURL = URL(string: template
                    .replacingOccurrences(of: "{z}", with: "0")
                    .replacingOccurrences(of: "{x}", with: "0")
                    .replacingOccurrences(of: "{y}", with: "0")) else {
                throw URLError(.badServerResponse)
            }
            _ = try await fetch(tileURL, session: session)
        }
    }

    private nonisolated static func fetch(_ url: URL, session: URLSession) async throws -> Data {
        // A cached answer would hide an outage.
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private nonisolated struct Style: Decodable {
        let sources: [String: Source]

        struct Source: Decodable {
            let type: String
            let url: URL?
        }
    }

    private nonisolated struct TileJSON: Decodable {
        let tiles: [String]
    }
}
