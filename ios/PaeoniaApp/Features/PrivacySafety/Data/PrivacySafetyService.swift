import Foundation

nonisolated protocol PrivacySafetyServicing: Sendable {
    func loadPrivacyRequests() async throws -> [PrivacyRequest]

    /// Emits the requests now and again whenever one changes on the server, newest
    /// first. The stream ends when the consuming task is cancelled.
    func privacyRequestUpdates() -> AsyncStream<[PrivacyRequest]>

    func submitPrivacyRequest(
        kind: PrivacyRequestKind,
        requesterNote: String?
    ) async throws -> PrivacyRequestSubmissionOutcome

    func submitReportAndLeave(
        target: PrivacyReportTarget,
        reason: PrivacyReportReason,
        note: String?,
        blockPartner: Bool,
        operation: SyncClientOperation
    ) async throws -> UUID
}

nonisolated extension PrivacySafetyServicing {
    /// Services without a live source emit nothing.
    func privacyRequestUpdates() -> AsyncStream<[PrivacyRequest]> {
        AsyncStream { $0.finish() }
    }
}

nonisolated enum PrivacySafetyServiceError: Error, Equatable {
    case requestSubmissionInProgress
}

actor PrivacySafetyService: PrivacySafetyServicing {
    private let gateway: any PrivacySafetyGateway
    private var submittingRequestKinds = Set<PrivacyRequestKind>()

    init(gateway: any PrivacySafetyGateway) {
        self.gateway = gateway
    }

    func loadPrivacyRequests() async throws -> [PrivacyRequest] {
        try await gateway
            .loadPrivacyRequests()
            .map(\.request)
            .sorted { $0.requestedAt > $1.requestedAt }
    }

    nonisolated func privacyRequestUpdates() -> AsyncStream<[PrivacyRequest]> {
        ScreenLiveUpdates.values(
            "identity:get_privacy_requests",
            as: [PrivacyRequestRemoteRow].self
        ) { rows in
            rows.map(\.request).sorted { $0.requestedAt > $1.requestedAt }
        }
    }

    func submitPrivacyRequest(
        kind: PrivacyRequestKind,
        requesterNote: String?
    ) async throws -> PrivacyRequestSubmissionOutcome {
        guard submittingRequestKinds.insert(kind).inserted else {
            throw PrivacySafetyServiceError.requestSubmissionInProgress
        }
        defer { submittingRequestKinds.remove(kind) }

        let requests = try await loadPrivacyRequests()
        if let activeRequest = requests.first(where: { $0.kind == kind && $0.isActive }) {
            return .alreadyActive(activeRequest)
        }

        let normalizedNote = requesterNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = try await gateway.createPrivacyRequest(
            id: UUID(),
            kind: kind,
            requesterNote: normalizedNote?.isEmpty == false ? normalizedNote : nil
        )
        return .created(row.request)
    }

    func submitReportAndLeave(
        target: PrivacyReportTarget,
        reason: PrivacyReportReason,
        note: String?,
        blockPartner: Bool,
        operation: SyncClientOperation
    ) async throws -> UUID {
        let normalizedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await gateway.submitReportAndLeave(
            target: target,
            reason: reason,
            note: normalizedNote?.isEmpty == false ? normalizedNote : nil,
            blockPartner: blockPartner,
            operation: operation
        )
    }
}

nonisolated enum PrivacySafetyServiceFactory {
    static func makeDefault() -> (any PrivacySafetyServicing)? {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return nil
        }

        return PrivacySafetyService(gateway: LivePrivacySafetyGateway(client: client))
    }
}
