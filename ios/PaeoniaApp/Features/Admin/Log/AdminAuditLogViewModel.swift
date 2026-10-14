import Observation

@MainActor
@Observable
final class AdminAuditLogViewModel {
    private(set) var entries = [AdminAuditEntry]()
    /// True once the first load finished, whether or not it worked.
    private(set) var hasLoaded = false
    private(set) var notice: AdminNotice?

    private let gateway: any AdminGateway

    init(gateway: any AdminGateway) {
        self.gateway = gateway
    }

    func load() async {
        do {
            let result = try await gateway.loadAuditLog(targetUserID: nil)
            guard !Task.isCancelled else {
                return
            }
            entries = result
            hasLoaded = true
        } catch {
            guard !Task.isCancelled, let failure = AdminNotice(loadError: error) else {
                return
            }
            notice = failure
            hasLoaded = true
        }
    }

    func dismissNotice() {
        notice = nil
    }
}
