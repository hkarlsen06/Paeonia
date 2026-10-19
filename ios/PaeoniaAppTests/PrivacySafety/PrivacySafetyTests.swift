import Foundation
import Testing
@testable import PaeoniaApp

struct PrivacySafetyServiceTests {
    @Test func reportRequestEncodesRequiredNullRPCArguments() throws {
        let request = SubmitReportAndLeaveRequest(
            target: .conduct(userID: UUID()),
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

    @Test func partnerAnswerReportEncodesTheAnswerAsItsSnapshotTarget() throws {
        let answerID = UUID()
        let request = SubmitReportAndLeaveRequest(
            target: .dailyAnswer(answerID: answerID),
            reason: .harassment,
            note: nil,
            blockPartner: true,
            operation: SyncClientOperation(clientID: UUID(), clientSequence: 2)
        )

        let data = try JSONEncoder().encode(request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["p_target_kind"] as? String == "daily_answer")
        let encodedTargetID = try #require(object["p_target_id"] as? String)
        #expect(UUID(uuidString: encodedTargetID) == answerID)
    }

    @Test func requestListSkipsRowsThisVersionCannotRead() throws {
        let json = """
        [
          {"id": "\(UUID().uuidString)", "request_kind": "access", "status": "submitted",
           "requested_at": "2026-03-01T10:00:00.000Z", "visible_status_message": null},
          {"id": "\(UUID().uuidString)", "request_kind": "deletion", "status": "submitted",
           "requested_at": "2026-03-02T10:00:00.000Z", "visible_status_message": null},
          {"id": "\(UUID().uuidString)", "request_kind": "export", "status": "archived",
           "requested_at": "2026-03-03T10:00:00.000Z", "visible_status_message": null},
          {"id": "\(UUID().uuidString)", "request_kind": "correction", "status": "completed",
           "requested_at": "2026-03-04T10:00:00.000Z", "visible_status_message": "Done"}
        ]
        """

        let list = try PaeoniaConvexClient.decoder.decode(
            PrivacyRequestRemoteRows.self,
            from: Data(json.utf8)
        )

        #expect(list.rows.map(\.requestKind) == [.access, .correction])
        #expect(list.rows.map(\.status) == [.submitted, .completed])
        #expect(list.rows.last?.visibleStatusMessage == "Done")
    }

    @Test func onlySelfHarmAndThreatsPointToEmergencyHelp() {
        let reasons = PrivacyReportReason.allCases.filter(\.suggestsEmergencyHelp)

        #expect(Set(reasons) == [.selfHarm, .threat])
    }

    @Test func activeRequestIsReusedInsteadOfCreatingDuplicate() async throws {
        let activeRow = makePrivacyRemoteRequest(kind: .export, status: .processing)
        let gateway = PrivacyFakeGateway(rows: [activeRow])
        let service = PrivacySafetyService(gateway: gateway)

        let outcome = try await service.submitPrivacyRequest(kind: .export, requesterNote: nil)

        #expect(outcome == .alreadyActive(activeRow.request))
        #expect(await gateway.createCallCount == 0)
    }

    @Test func terminalRequestAllowsNewRequest() async throws {
        let oldRow = makePrivacyRemoteRequest(kind: .access, status: .completed)
        let createdRow = makePrivacyRemoteRequest(
            kind: .access,
            status: .submitted,
            requestedAt: Date(timeIntervalSince1970: 20)
        )
        let gateway = PrivacyFakeGateway(rows: [oldRow], createdRow: createdRow)
        let service = PrivacySafetyService(gateway: gateway)

        let outcome = try await service.submitPrivacyRequest(kind: .access, requesterNote: nil)

        #expect(outcome == .created(createdRow.request))
        #expect(await gateway.createCallCount == 1)
    }

    @Test func reportSubmissionTrimsNoteAndForwardsExplicitBlockChoice() async throws {
        let gateway = PrivacyFakeGateway()
        let service = PrivacySafetyService(gateway: gateway)
        let partnerID = UUID()
        let operation = SyncClientOperation(
            id: UUID(),
            clientID: UUID(),
            clientSequence: 7,
            localCreatedAt: Date(timeIntervalSince1970: 30)
        )

        _ = try await service.submitReportAndLeave(
            target: .conduct(userID: partnerID),
            reason: .privacy,
            note: "  Shared a private photo  ",
            blockPartner: false,
            operation: operation
        )

        let submission = await gateway.lastReportSubmission
        #expect(submission?.target == .conduct(userID: partnerID))
        #expect(submission?.reason == .privacy)
        #expect(submission?.note == "Shared a private photo")
        #expect(submission?.blockPartner == false)
        #expect(submission?.operation == operation)
    }
}

@MainActor
struct PrivacySafetyViewModelTests {
    @Test func correctionRequiresUsefulDetailsBeforeCallingService() async {
        let service = PrivacyFakeService()
        let viewModel = PrivacySafetyViewModel(service: service)

        let didSubmit = await viewModel.submitRequest(kind: .correction, requesterNote: "   ")

        #expect(didSubmit == false)
        #expect(viewModel.notice == .correctionDetailsRequired)
        #expect(await service.privacyRequestCallCount == 0)
    }
}

@MainActor
struct ReportAndLeaveViewModelTests {
    @Test func successfulReportUsesCurrentPartnerAndDoesNotSurpriseBlock() async {
        let service = PrivacyFakeService()
        let operationProvider = PrivacyFixedOperationProvider()
        let viewModel = ReportAndLeaveViewModel(
            service: service,
            operationProvider: operationProvider
        )
        let partnerID = UUID()
        viewModel.selectedReason = .harassment
        viewModel.note = "Repeated unwanted messages"

        let didSubmit = await viewModel.submit(target: .conduct(userID: partnerID))

        #expect(didSubmit)
        #expect(viewModel.didSubmit)
        #expect(viewModel.notice == nil)
        #expect(viewModel.isSubmitting == false)
        let submission = await service.lastReportSubmission
        #expect(submission?.target == .conduct(userID: partnerID))
        #expect(submission?.blockPartner == false)
        #expect(submission?.operation == operationProvider.operation)
    }

    @Test func secondReportIsBlockedAfterASuccessfulOne() async {
        let service = PrivacyFakeService()
        let viewModel = ReportAndLeaveViewModel(
            service: service,
            operationProvider: PrivacyIncrementingOperationProvider()
        )
        let target = PrivacyReportTarget.conduct(userID: UUID())
        viewModel.selectedReason = .harassment

        #expect(await viewModel.submit(target: target))
        #expect(viewModel.didSubmit)
        #expect(viewModel.canSubmit == false)
        #expect(viewModel.prepareConfirmation() == false)

        #expect(await viewModel.submit(target: target) == false)
        #expect(await service.reportOperations.count == 1)
    }

    @Test func secondReportIsBlockedWhileTheFirstIsStillSending() async {
        let service = PrivacyGatedReportService()
        let viewModel = ReportAndLeaveViewModel(
            service: service,
            operationProvider: PrivacyIncrementingOperationProvider()
        )
        let target = PrivacyReportTarget.conduct(userID: UUID())
        viewModel.selectedReason = .abuse

        let firstSubmission = Task { await viewModel.submit(target: target) }
        while !viewModel.isSubmitting {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.canSubmit == false)
        #expect(await viewModel.submit(target: target) == false)

        await service.release()
        #expect(await firstSubmission.value)
        #expect(await service.reportCallCount == 1)
        #expect(viewModel.didSubmit)
    }

    @Test func explicitBlockChoiceIsForwarded() async {
        let service = PrivacyFakeService()
        let viewModel = ReportAndLeaveViewModel(
            service: service,
            operationProvider: PrivacyFixedOperationProvider()
        )
        viewModel.selectedReason = .threat
        viewModel.blockPartner = true

        let didSubmit = await viewModel.submit(target: .conduct(userID: UUID()))

        #expect(didSubmit)
        #expect(await service.lastReportSubmission?.blockPartner == true)
    }

    @Test func retryAfterLostResponseReusesIdempotencyOperation() async {
        let service = PrivacyFakeService(failFirstReport: true)
        let viewModel = ReportAndLeaveViewModel(
            service: service,
            operationProvider: PrivacyIncrementingOperationProvider()
        )
        let partnerID = UUID()
        viewModel.selectedReason = .privacy
        viewModel.note = "  Shared private details  "

        #expect(await viewModel.submit(target: .conduct(userID: partnerID)) == false)
        #expect(await viewModel.submit(target: .conduct(userID: partnerID)) == true)

        let operations = await service.reportOperations
        #expect(operations.count == 2)
        #expect(operations.first == operations.last)
    }

    @Test func changedReportDraftUsesANewIdempotencyOperation() async {
        let service = PrivacyFakeService(failFirstReport: true)
        let viewModel = ReportAndLeaveViewModel(
            service: service,
            operationProvider: PrivacyIncrementingOperationProvider()
        )
        let partnerID = UUID()
        viewModel.selectedReason = .other
        viewModel.note = "First description"

        #expect(await viewModel.submit(target: .conduct(userID: partnerID)) == false)
        viewModel.note = "Corrected description"
        #expect(await viewModel.submit(target: .conduct(userID: partnerID)) == true)

        let operations = await service.reportOperations
        #expect(operations.count == 2)
        #expect(operations.first != operations.last)
    }
}
