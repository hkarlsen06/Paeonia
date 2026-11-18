import Foundation
import Observation

/// What the paywall's location switch needs from the server.
protocol PaywallLocationSharingGateway: Sendable {
    /// The signed-in person's couple and whether they share their location in it.
    /// Nil without a couple.
    func ownLocationSharing() async throws -> OwnLocationSharing?
    func turnOffLocationSharing(coupleID: UUID, operation: SyncClientOperation) async throws
}

nonisolated struct OwnLocationSharing: Decodable, Equatable, Sendable {
    let coupleID: UUID
    let isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case isEnabled = "is_enabled"
    }
}

/// Location sharing on the paywall, where the paid app's own switch is out of
/// reach. A couple without access keeps nothing about location on the phone
/// (`hideRelationshipAccess`), so this asks the server whether sharing is on and
/// turns it off there. Turning it on needs access, so the switch only goes off here.
@Observable
final class PaywallLocationSharingModel {
    enum State: Equatable {
        case loading
        case loadFailed
        /// The person has no couple, so there is nothing to switch.
        case noCouple
        case loaded(isEnabled: Bool)
    }

    private(set) var state = State.loading
    private(set) var isSaving = false
    /// Why the last try to turn sharing off failed. The sheet shows it once.
    private(set) var failure: PaeoniaFailure?

    private let gateway: (any PaywallLocationSharingGateway)?
    private let operationProvider: any SyncClientOperationProviding
    private var coupleID: UUID?

    init(
        gateway: (any PaywallLocationSharingGateway)?,
        operationProvider: (any SyncClientOperationProviding)? = nil
    ) {
        self.gateway = gateway
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
    }

    var isEnabled: Bool {
        state == .loaded(isEnabled: true)
    }

    func load() async {
        guard !isSaving else {
            return
        }
        guard let gateway else {
            state = .loadFailed
            return
        }
        do {
            let sharing = try await gateway.ownLocationSharing()
            guard !isSaving else {
                return
            }
            coupleID = sharing?.coupleID
            state = sharing.map { .loaded(isEnabled: $0.isEnabled) } ?? .noCouple
        } catch {
            if state == .loading {
                state = .loadFailed
            }
        }
    }

    func turnOff() async {
        guard let gateway, let coupleID, isEnabled, !isSaving else {
            return
        }
        isSaving = true
        defer { isSaving = false }
        state = .loaded(isEnabled: false)
        do {
            try await gateway.turnOffLocationSharing(coupleID: coupleID, operation: operationProvider.makeOperation())
        } catch {
            state = .loaded(isEnabled: true)
            failure = PaeoniaFailure(error)
        }
    }

    func clearFailure() {
        failure = nil
    }
}

enum PaywallLocationSharingGatewayFactory {
    static func makeDefault() -> (any PaywallLocationSharingGateway)? {
        (try? PaeoniaConvexClientProvider.shared.client()).map { LiveLocationGateway(client: $0) }
    }
}
