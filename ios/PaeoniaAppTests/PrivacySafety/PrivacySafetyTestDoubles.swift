import Foundation
import Testing
@testable import PaeoniaApp

// Test doubles for the privacy and safety tests.

nonisolated enum PrivacyFakeError: Error {
    case failed
}

nonisolated struct PrivacyCapturedReportSubmission: Equatable, Sendable {
    let target: PrivacyReportTarget
    let reason: PrivacyReportReason
    let note: String?
    let blockPartner: Bool
    let operation: SyncClientOperation
}

actor PrivacyFakeGateway: PrivacySafetyGateway {
    private let rows: [PrivacyRequestRemoteRow]
    private let createdRow: PrivacyRequestRemoteRow?
    private(set) var createCallCount = 0
    private(set) var lastReportSubmission: PrivacyCapturedReportSubmission?

    init(
        rows: [PrivacyRequestRemoteRow] = [],
        createdRow: PrivacyRequestRemoteRow? = nil
    ) {
        self.rows = rows
        self.createdRow = createdRow
    }

    func loadPrivacyRequests() -> [PrivacyRequestRemoteRow] {
        rows
    }

    func createPrivacyRequest(
        id: UUID,
        kind: PrivacyRequestKind,
        requesterNote: String?
    ) throws -> PrivacyRequestRemoteRow {
        createCallCount += 1
        guard let createdRow else {
            throw PrivacyFakeError.failed
        }
        return createdRow
    }

    func submitReportAndLeave(
        target: PrivacyReportTarget,
        reason: PrivacyReportReason,
        note: String?,
        blockPartner: Bool,
        operation: SyncClientOperation
    ) -> UUID {
        lastReportSubmission = PrivacyCapturedReportSubmission(
            target: target,
            reason: reason,
            note: note,
            blockPartner: blockPartner,
            operation: operation
        )
        return UUID()
    }
}

actor PrivacyFakeService: PrivacySafetyServicing {
    private let requests: [PrivacyRequest]
    private let requestOutcome: PrivacyRequestSubmissionOutcome?
    private let failPrivacyRequest: Bool
    private let failReport: Bool
    private let failFirstReport: Bool
    private let loadError: (any Error)?
    private var didFailFirstReport = false
    private let updates = AsyncStream<[PrivacyRequest]>.makeStream()
    private(set) var privacyRequestCallCount = 0
    private(set) var lastReportSubmission: PrivacyCapturedReportSubmission?
    private(set) var reportOperations = [SyncClientOperation]()

    init(
        requests: [PrivacyRequest] = [],
        requestOutcome: PrivacyRequestSubmissionOutcome? = nil,
        failPrivacyRequest: Bool = false,
        failReport: Bool = false,
        failFirstReport: Bool = false,
        loadError: (any Error)? = nil
    ) {
        self.loadError = loadError
        self.requests = requests
        self.requestOutcome = requestOutcome
        self.failPrivacyRequest = failPrivacyRequest
        self.failReport = failReport
        self.failFirstReport = failFirstReport
    }

    func loadPrivacyRequests() throws -> [PrivacyRequest] {
        if let loadError {
            throw loadError
        }
        return requests
    }

    nonisolated func privacyRequestUpdates() -> AsyncStream<[PrivacyRequest]> {
        updates.stream
    }

    func emit(_ requests: [PrivacyRequest]) {
        updates.continuation.yield(requests)
    }

    func submitPrivacyRequest(
        kind: PrivacyRequestKind,
        requesterNote: String?
    ) throws -> PrivacyRequestSubmissionOutcome {
        privacyRequestCallCount += 1
        if failPrivacyRequest {
            throw PrivacyFakeError.failed
        }
        guard let requestOutcome else {
            throw PrivacyFakeError.failed
        }
        return requestOutcome
    }

    func submitReportAndLeave(
        target: PrivacyReportTarget,
        reason: PrivacyReportReason,
        note: String?,
        blockPartner: Bool,
        operation: SyncClientOperation
    ) throws -> UUID {
        reportOperations.append(operation)
        if failReport || (failFirstReport && !didFailFirstReport) {
            didFailFirstReport = true
            throw PrivacyFakeError.failed
        }
        lastReportSubmission = PrivacyCapturedReportSubmission(
            target: target,
            reason: reason,
            note: note,
            blockPartner: blockPartner,
            operation: operation
        )
        return UUID()
    }
}

/// Holds a report in flight until the test calls `release()`.
actor PrivacyGatedReportService: PrivacySafetyServicing {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false
    private(set) var reportCallCount = 0

    func loadPrivacyRequests() -> [PrivacyRequest] {
        []
    }

    func submitPrivacyRequest(
        kind: PrivacyRequestKind,
        requesterNote: String?
    ) throws -> PrivacyRequestSubmissionOutcome {
        throw PrivacyFakeError.failed
    }

    func submitReportAndLeave(
        target: PrivacyReportTarget,
        reason: PrivacyReportReason,
        note: String?,
        blockPartner: Bool,
        operation: SyncClientOperation
    ) async -> UUID {
        reportCallCount += 1
        if !isReleased {
            await withCheckedContinuation { continuation = $0 }
        }
        return UUID()
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class PrivacyFixedOperationProvider: SyncClientOperationProviding {
    let operation: SyncClientOperation

    init() {
        operation = SyncClientOperation(
            id: UUID(),
            clientID: UUID(),
            clientSequence: 3,
            localCreatedAt: Date(timeIntervalSince1970: 40)
        )
    }

    func makeOperation() -> SyncClientOperation {
        operation
    }
}

@MainActor
final class PrivacyIncrementingOperationProvider: SyncClientOperationProviding {
    private let clientID = UUID()
    private var nextSequence: Int64 = 1

    func makeOperation() -> SyncClientOperation {
        defer { nextSequence += 1 }
        return SyncClientOperation(
            id: UUID(),
            clientID: clientID,
            clientSequence: nextSequence,
            localCreatedAt: Date(timeIntervalSince1970: TimeInterval(nextSequence))
        )
    }
}

nonisolated func makePrivacyRequest(
    kind: PrivacyRequestKind,
    status: PrivacyRequestStatus,
    requestedAt: Date = Date(timeIntervalSince1970: 10)
) -> PrivacyRequest {
    PrivacyRequest(
        id: UUID(),
        kind: kind,
        status: status,
        requestedAt: requestedAt,
        visibleStatusMessage: nil
    )
}

nonisolated func makePrivacyRemoteRequest(
    kind: PrivacyRequestKind,
    status: PrivacyRequestStatus,
    requestedAt: Date = Date(timeIntervalSince1970: 10)
) -> PrivacyRequestRemoteRow {
    PrivacyRequestRemoteRow(
        id: UUID(),
        requestKind: kind,
        status: status,
        requestedAt: requestedAt,
        visibleStatusMessage: nil
    )
}
