import Observation

@MainActor
@Observable
final class AdminAuditLogViewModel {
    private(set) var entries = [AdminAuditEntry]()
    /// True once a read succeeded.
    private(set) var hasLoaded = false
    private(set) var loadFailure: PaeoniaFailure?
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
            loadFailure = nil
        } catch {
            guard !Task.isCancelled, let failure = AdminNotice(loadError: error) else {
                return
            }
            notice = failure
            loadFailure = PaeoniaFailure(error)
        }
    }

    func dismissNotice() {
        notice = nil
    }
}
