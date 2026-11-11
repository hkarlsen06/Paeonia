import Foundation
import Observation
import OSLog

/// Reachability of Home's map endpoints. Rendering delays do not establish an outage.
nonisolated enum HomeMapTiles: Equatable, Sendable {
    case trying
    case available
    /// The map stays visible while the phone has no connection.
    case offline
    /// An endpoint check failed. The map card stays until a check succeeds.
    case unavailable(retryAfter: Date)
}

@Observable
final class HomeMapTileStatus {
    private(set) var tiles: HomeMapTiles = .trying
    let styleURL: URL
    @ObservationIgnored private let check: (URL) async throws -> Void
    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private var loadRevision = 0

    static let loadTimeout: Duration = .seconds(10)
    private static let retryDelay: TimeInterval = 60
    nonisolated static let logger = Logger(subsystem: "no.paeonia.app", category: "HomeMap")

    init(
        styleURL: URL = HomeMapLibreView.styleURL,
        check: @escaping (URL) async throws -> Void = { try await HomeMapTileStatus.fetchStyle($0) }
    ) {
        self.styleURL = styleURL
        self.check = check
    }

    var showsMapHeader: Bool {
        if case .unavailable = tiles { false } else { true }
    }

    func mapLoaded() {
        loadRevision += 1
        Self.logger.notice("Map finished loading")
        update(.available)
    }

    /// A render delay or delegate error prompts a separate reachability check.
    func mapDidNotLoad() async {
        guard showsMapHeader else { return }
        await checkTiles()
    }

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

    /// Returning to the app can recover immediately, without waiting for the retry date.
    func checkOnReturn() async {
        switch tiles {
        case .offline, .unavailable:
            await checkTiles()
        case .trying, .available:
            break
        }
    }

    func watch() async {
        await checkIfDue()
        while let delay = nextCheck {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await checkTiles()
        }
    }

    private var nextCheck: Duration? {
        switch tiles {
        case .trying, .available:
            return nil
        case .offline:
            return .seconds(30)
        case let .unavailable(retryAfter):
            return .seconds(max(1, retryAfter.timeIntervalSinceNow))
        }
    }

    private func checkTiles() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let revision = loadRevision
        let failure: PaeoniaFailure?
        do {
            try await check(styleURL)
            failure = nil
            Self.logger.notice("Map endpoint check succeeded")
        } catch is CancellationError {
            Self.logger.debug("Map endpoint check cancelled")
            return
        } catch let error as URLError where error.code == .cancelled {
            Self.logger.debug("Map endpoint request cancelled")
            return
        } catch {
            let underlying = error as NSError
            Self.logger.error("""
                Map endpoint check failed: domain=\(underlying.domain, privacy: .public) \
                code=\(underlying.code) detail=\(underlying.localizedDescription, privacy: .private)
                """)
            failure = PaeoniaFailure(error)
        }
        // A completed map takes precedence over an older probe.
        guard loadRevision == revision, !Task.isCancelled else { return }
        applyProbeResult(failure)
    }

    private func applyProbeResult(_ failure: PaeoniaFailure?) {
        switch failure {
        case nil:
            update(.available)
        case .offline:
            if case .unavailable = tiles {
                update(.unavailable(retryAfter: .now.addingTimeInterval(Self.retryDelay)))
            } else {
                update(.offline)
            }
        case .other:
            update(.unavailable(retryAfter: .now.addingTimeInterval(Self.retryDelay)))
        }
    }

    private func update(_ next: HomeMapTiles) {
        guard tiles != next else { return }
        Self.logger.notice("""
            Map reachability changed: \(String(describing: self.tiles), privacy: .public) \
            to \(String(describing: next), privacy: .public)
            """)
        tiles = next
    }
}

extension HomeMapTileStatus {
    /// Checks a world tile too. The style and its source description can work while
    /// OpenFreeMap's tile server is down.
    nonisolated static func fetchStyle(_ url: URL, session: URLSession = .paeonia) async throws {
        let style = try await JSONDecoder().decode(Style.self, from: fetch(url, stage: "style", session: session))
        for source in style.sources.values where source.type == "vector" {
            guard let sourceURL = source.url else { throw URLError(.badServerResponse) }
            let tileJSON = try await JSONDecoder().decode(
                TileJSON.self, from: fetch(sourceURL, stage: "source", session: session)
            )
            guard let template = tileJSON.tiles.first,
                  let tileURL = URL(string: template
                    .replacingOccurrences(of: "{z}", with: "0")
                    .replacingOccurrences(of: "{x}", with: "0")
                    .replacingOccurrences(of: "{y}", with: "0")) else {
                throw URLError(.badServerResponse)
            }
            _ = try await fetch(tileURL, stage: "world tile", session: session)
        }
    }

    private nonisolated static func fetch(
        _ url: URL, stage: String, session: URLSession
    ) async throws -> Data {
        // A cached answer would hide an outage.
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        logger.notice("Checking map endpoint: \(stage, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        logger.notice("Endpoint check: \(stage, privacy: .public), HTTP \(status)")
        guard (200..<300).contains(status) else {
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
