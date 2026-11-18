import Observation

/// The reports and correction requests that wait for an admin.
@Observable
final class AdminOpenCasesViewModel {
    private(set) var reports = [AdminOpenReport]()
    private(set) var correctionRequests = [AdminCorrectionRequest]()
    /// True once a read succeeded.
    private(set) var hasLoaded = false
    private(set) var loadFailure: PaeoniaFailure?
    private(set) var notice: AdminNotice?

    private let gateway: any AdminGateway

    init(gateway: any AdminGateway) {
        self.gateway = gateway
    }

    var isEmpty: Bool { reports.isEmpty && correctionRequests.isEmpty }

    func load() async {
        do {
            async let openReports = gateway.loadOpenReports()
            async let openRequests = gateway.loadOpenCorrectionRequests()
            let result = try await (openReports, openRequests)
            guard !Task.isCancelled else {
                return
            }
            (reports, correctionRequests) = result
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
