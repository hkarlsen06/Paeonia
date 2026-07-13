import Foundation
import Testing
@testable import PaeoniaApp

struct PrivacySafetyServiceTests {
    @Test func reportRequestEncodesRequiredNullRPCArguments() throws {
        let request = SubmitConductReportAndLeaveRequest(
            partnerUserID: UUID(),
            reason: .other,
            note: nil,
            blockPartner: false,
            operation: SyncClientOperation(clientID: UUID(), clientSequence: 1)
        )

        let data = try JSONEncoder().encode(request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["p_note"] is NSNull)
        #expect(object["p_target_aux_id"] is NSNull)
        #expect(object["p_target_kind"] as? String == "conduct")
    }

    @Test func activeRequestIsReusedInsteadOfCreatingDuplicate() async throws {
        let activeRow = makeRemoteRequest(kind: .export, status: .processing)
        let gateway = FakePrivacySafetyGateway(rows: [activeRow])
        let service = PrivacySafetyService(gateway: gateway)

        let outcome = try await service.submitPrivacyRequest(kind: .export, requesterNote: nil)

        #expect(outcome == .alreadyActive(activeRow.request))
        #expect(await gateway.createCallCount == 0)
    }

    @Test func terminalRequestAllowsNewRequest() async throws {
        let oldRow = makeRemoteRequest(kind: .access, status: .completed)
        let createdRow = makeRemoteRequest(
            kind: .access,
            status: .submitted,
            requestedAt: Date(timeIntervalSince1970: 20)
        )
        let gateway = FakePrivacySafetyGateway(rows: [oldRow], createdRow: createdRow)
        let service = PrivacySafetyService(gateway: gateway)

        let outcome = try await service.submitPrivacyRequest(kind: .access, requesterNote: nil)

        #expect(outcome == .created(createdRow.request))
        #expect(await gateway.createCallCount == 1)
    }

    @Test func reportSubmissionTrimsNoteAndForwardsExplicitBlockChoice() async throws {
        let gateway = FakePrivacySafetyGateway()
        let service = PrivacySafetyService(gateway: gateway)
        let partnerID = UUID()
        let operation = SyncClientOperation(
            id: UUID(),
            clientID: UUID(),
            clientSequence: 7,
            localCreatedAt: Date(timeIntervalSince1970: 30)
        )

        _ = try await service.submitConductReportAndLeave(
            partnerUserID: partnerID,
            reason: .privacy,
            note: "  Shared a private photo  ",
            blockPartner: false,
            operation: operation
        )

        let submission = await gateway.lastReportSubmission
        #expect(submission?.partnerUserID == partnerID)
        #expect(submission?.reason == .privacy)
        #expect(submission?.note == "Shared a private photo")
        #expect(submission?.blockPartner == false)
        #expect(submission?.operation == operation)
    }
}

@MainActor
struct PrivacySafetyViewModelTests {
    @Test func successfulRequestUpdatesVisibleStateAndNotice() async {
        let request = makeRequest(kind: .access, status: .submitted)
        let service = FakePrivacySafetyService(requestOutcome: .created(request))
        let viewModel = PrivacySafetyViewModel(service: service)

        let didSubmit = await viewModel.submitRequest(kind: .access)

        #expect(didSubmit)
        #expect(viewModel.latestRequest(for: .access) == request)
        #expect(viewModel.notice == .requestSubmitted(.access))
    }

    @Test func alreadyActiveRequestProducesUnderstandableNotice() async {
        let request = makeRequest(kind: .export, status: .verifying)
        let service = FakePrivacySafetyService(requestOutcome: .alreadyActive(request))
        let viewModel = PrivacySafetyViewModel(service: service)

        let didSubmit = await viewModel.submitRequest(kind: .export)

        #expect(didSubmit)
        #expect(viewModel.notice == .requestAlreadyActive(.export))
    }

    @Test func correctionRequiresUsefulDetailsBeforeCallingService() async {
        let service = FakePrivacySafetyService()
        let viewModel = PrivacySafetyViewModel(service: service)

        let didSubmit = await viewModel.submitRequest(kind: .correction, requesterNote: "   ")

        #expect(didSubmit == false)
        #expect(viewModel.notice == .correctionDetailsRequired)
        #expect(await service.privacyRequestCallCount == 0)
    }

    @Test func requestFailureLeavesNoFalseSuccessState() async {
        let service = FakePrivacySafetyService(failPrivacyRequest: true)
        let viewModel = PrivacySafetyViewModel(service: service)

        let didSubmit = await viewModel.submitRequest(kind: .access)

        #expect(didSubmit == false)
        #expect(viewModel.requests.isEmpty)
        #expect(viewModel.notice == .requestFailed)
    }
}

@MainActor
struct ReportAndLeaveViewModelTests {
    @Test func blockingIsOffByDefaultAndReasonIsRequired() {
        let viewModel = ReportAndLeaveViewModel(
            service: FakePrivacySafetyService(),
            operationProvider: FixedOperationProvider()
        )

        #expect(viewModel.blockPartner == false)
        #expect(viewModel.prepareConfirmation() == false)
        #expect(viewModel.notice == .reasonRequired)
    }

    @Test func successfulReportUsesCurrentPartnerAndDoesNotSurpriseBlock() async {
        let service = FakePrivacySafetyService()
        let operationProvider = FixedOperationProvider()
        let viewModel = ReportAndLeaveViewModel(
            service: service,
            operationProvider: operationProvider
        )
        let partnerID = UUID()
        viewModel.selectedReason = .harassment
        viewModel.note = "Repeated unwanted messages"

        let didSubmit = await viewModel.submit(partnerUserID: partnerID)

        #expect(didSubmit)
        #expect(viewModel.notice == .submitted)
        #expect(viewModel.isSubmitting == false)
        let submission = await service.lastReportSubmission
        #expect(submission?.partnerUserID == partnerID)
        #expect(submission?.blockPartner == false)
        #expect(submission?.operation == operationProvider.operation)
    }

    @Test func explicitBlockChoiceIsForwarded() async {
        let service = FakePrivacySafetyService()
        let viewModel = ReportAndLeaveViewModel(
            service: service,
            operationProvider: FixedOperationProvider()
        )
        viewModel.selectedReason = .threat
        viewModel.blockPartner = true

        let didSubmit = await viewModel.submit(partnerUserID: UUID())

        #expect(didSubmit)
        #expect(await service.lastReportSubmission?.blockPartner == true)
    }

    @Test func failedReportKeepsRelationshipRefreshCallbackFromFalseSuccess() async {
        let service = FakePrivacySafetyService(failReport: true)
        let viewModel = ReportAndLeaveViewModel(
            service: service,
            operationProvider: FixedOperationProvider()
        )
        viewModel.selectedReason = .other

        let didSubmit = await viewModel.submit(partnerUserID: UUID())

        #expect(didSubmit == false)
        #expect(viewModel.notice == .submitFailed)
        #expect(viewModel.isSubmitting == false)
    }

    @Test func retryAfterLostResponseReusesIdempotencyOperation() async {
        let service = FakePrivacySafetyService(failFirstReport: true)
        let viewModel = ReportAndLeaveViewModel(
            service: service,
            operationProvider: IncrementingOperationProvider()
        )
        let partnerID = UUID()
        viewModel.selectedReason = .privacy
        viewModel.note = "  Shared private details  "

        #expect(await viewModel.submit(partnerUserID: partnerID) == false)
        #expect(await viewModel.submit(partnerUserID: partnerID) == true)

        let operations = await service.reportOperations
        #expect(operations.count == 2)
        #expect(operations.first == operations.last)
    }

    @Test func changedReportDraftUsesANewIdempotencyOperation() async {
        let service = FakePrivacySafetyService(failFirstReport: true)
        let viewModel = ReportAndLeaveViewModel(
            service: service,
            operationProvider: IncrementingOperationProvider()
        )
        let partnerID = UUID()
        viewModel.selectedReason = .other
        viewModel.note = "First description"

        #expect(await viewModel.submit(partnerUserID: partnerID) == false)
        viewModel.note = "Corrected description"
        #expect(await viewModel.submit(partnerUserID: partnerID) == true)

        let operations = await service.reportOperations
        #expect(operations.count == 2)
        #expect(operations.first != operations.last)
    }
}

nonisolated private enum FakePrivacySafetyError: Error {
    case failed
}

nonisolated private struct CapturedReportSubmission: Equatable, Sendable {
    let partnerUserID: UUID
    let reason: PrivacyReportReason
    let note: String?
    let blockPartner: Bool
    let operation: SyncClientOperation
}

private actor FakePrivacySafetyGateway: PrivacySafetyGateway {
    private let rows: [PrivacyRequestRemoteRow]
    private let createdRow: PrivacyRequestRemoteRow?
    private(set) var createCallCount = 0
    private(set) var lastReportSubmission: CapturedReportSubmission?

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
            throw FakePrivacySafetyError.failed
        }
        return createdRow
    }

    func submitConductReportAndLeave(
        partnerUserID: UUID,
        reason: PrivacyReportReason,
        note: String?,
        blockPartner: Bool,
        operation: SyncClientOperation
    ) -> UUID {
        lastReportSubmission = CapturedReportSubmission(
            partnerUserID: partnerUserID,
            reason: reason,
            note: note,
            blockPartner: blockPartner,
            operation: operation
        )
        return UUID()
    }
}

private actor FakePrivacySafetyService: PrivacySafetyServicing {
    private let requests: [PrivacyRequest]
    private let requestOutcome: PrivacyRequestSubmissionOutcome?
    private let failPrivacyRequest: Bool
    private let failReport: Bool
    private let failFirstReport: Bool
    private var didFailFirstReport = false
    private(set) var privacyRequestCallCount = 0
    private(set) var lastReportSubmission: CapturedReportSubmission?
    private(set) var reportOperations = [SyncClientOperation]()

    init(
        requests: [PrivacyRequest] = [],
        requestOutcome: PrivacyRequestSubmissionOutcome? = nil,
        failPrivacyRequest: Bool = false,
        failReport: Bool = false,
        failFirstReport: Bool = false
    ) {
        self.requests = requests
        self.requestOutcome = requestOutcome
        self.failPrivacyRequest = failPrivacyRequest
        self.failReport = failReport
        self.failFirstReport = failFirstReport
    }

    func loadPrivacyRequests() -> [PrivacyRequest] {
        requests
    }

    func submitPrivacyRequest(
        kind: PrivacyRequestKind,
        requesterNote: String?
    ) throws -> PrivacyRequestSubmissionOutcome {
        privacyRequestCallCount += 1
        if failPrivacyRequest {
            throw FakePrivacySafetyError.failed
        }
        guard let requestOutcome else {
            throw FakePrivacySafetyError.failed
        }
        return requestOutcome
    }

    func submitConductReportAndLeave(
        partnerUserID: UUID,
        reason: PrivacyReportReason,
        note: String?,
        blockPartner: Bool,
        operation: SyncClientOperation
    ) throws -> UUID {
        reportOperations.append(operation)
        if failReport || (failFirstReport && !didFailFirstReport) {
            didFailFirstReport = true
            throw FakePrivacySafetyError.failed
        }
        lastReportSubmission = CapturedReportSubmission(
            partnerUserID: partnerUserID,
            reason: reason,
            note: note,
            blockPartner: blockPartner,
            operation: operation
        )
        return UUID()
    }
}

@MainActor
private final class FixedOperationProvider: SyncClientOperationProviding {
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
private final class IncrementingOperationProvider: SyncClientOperationProviding {
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

nonisolated private func makeRequest(
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

nonisolated private func makeRemoteRequest(
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
