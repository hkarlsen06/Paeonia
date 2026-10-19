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

actor PrivacyFakeGateway {
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

extension PrivacyFakeGateway: PrivacySafetyGateway {}

actor PrivacyFakeService {
    private let failFirstReport: Bool
    private var didFailFirstReport = false
    private(set) var privacyRequestCallCount = 0
    private(set) var lastReportSubmission: PrivacyCapturedReportSubmission?
    private(set) var reportOperations = [SyncClientOperation]()

    init(failFirstReport: Bool = false) {
        self.failFirstReport = failFirstReport
    }

    func loadPrivacyRequests() throws -> [PrivacyRequest] {
        []
    }

    nonisolated func privacyRequestUpdates() -> AsyncStream<[PrivacyRequest]> {
        AsyncStream { _ in }
    }

    func submitPrivacyRequest(
        kind: PrivacyRequestKind,
        requesterNote: String?
    ) throws -> PrivacyRequestSubmissionOutcome {
        privacyRequestCallCount += 1
        throw PrivacyFakeError.failed
    }

    func submitReportAndLeave(
        target: PrivacyReportTarget,
        reason: PrivacyReportReason,
        note: String?,
        blockPartner: Bool,
        operation: SyncClientOperation
    ) throws -> UUID {
        reportOperations.append(operation)
        if failFirstReport && !didFailFirstReport {
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

extension PrivacyFakeService: PrivacySafetyServicing {}

/// Holds a report in flight until the test calls `release()`.
actor PrivacyGatedReportService {
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

extension PrivacyGatedReportService: PrivacySafetyServicing {}

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
