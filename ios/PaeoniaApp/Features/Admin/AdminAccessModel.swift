import Observation

/// Whether to show the Admin row. The server checks admin access again on every
/// admin call, so this only hides the row. It fails closed: any error hides it.
@MainActor
@Observable
final class AdminAccessModel {
    private(set) var isAdmin = false

    private let gateway: (any AdminGateway)?

    init(gateway: (any AdminGateway)?) {
        self.gateway = gateway
    }

    func refresh() async {
        guard let gateway else {
            isAdmin = false
            return
        }
        do {
            let result = try await gateway.loadIsAdmin()
            guard !Task.isCancelled else {
                return
            }
            isAdmin = result
        } catch {
            // A cancelled check says nothing about the account. Keep what we knew.
            guard AdminFailure(error) != .cancelled else {
                return
            }
            isAdmin = false
        }
    }
}
