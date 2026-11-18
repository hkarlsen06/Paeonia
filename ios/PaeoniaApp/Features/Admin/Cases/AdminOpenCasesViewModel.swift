import Foundation
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
    /// The cases a close call is running for, so a second tap does nothing.
    private var closing = Set<UUID>()

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

    /// Marks a case as handled and takes it off the list. Returns true when it went through.
    @discardableResult
    func markHandled(_ openCase: AdminOpenCase) async -> Bool {
        guard closing.insert(openCase.id).inserted else {
            return false
        }
        defer { closing.remove(openCase.id) }

        do {
            try await gateway.close(openCase)
        } catch {
            notice = AdminNotice(closeError: error)
            return false
        }
        switch openCase {
        case let .report(id): reports.removeAll { $0.id == id }
        case let .correctionRequest(id): correctionRequests.removeAll { $0.id == id }
        }
        notice = .caseHandled
        return true
    }

    func dismissNotice() {
        notice = nil
    }
}
