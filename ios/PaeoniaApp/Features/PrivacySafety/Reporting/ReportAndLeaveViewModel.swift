import Foundation
import Observation

@MainActor
@Observable
final class ReportAndLeaveViewModel {
    enum Notice: Equatable {
        case reasonRequired
        case submitFailed
        case submitted
    }

    private let service: (any PrivacySafetyServicing)?
    private let operationProvider: any SyncClientOperationProviding
    private var pendingSubmission: PendingSubmission?

    var selectedReason: PrivacyReportReason?
    var note = ""
    /// Blocking is deliberately opt-in. Never infer it from opening this flow or
    /// from the reason the user selects.
    var blockPartner = false

    private(set) var isSubmitting = false
    private(set) var notice: Notice?

    init(
        service: (any PrivacySafetyServicing)? = PrivacySafetyServiceFactory.makeDefault(),
        operationProvider: (any SyncClientOperationProviding)? = nil
    ) {
        self.service = service
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
    }

    func prepareConfirmation() -> Bool {
        guard selectedReason != nil else {
            notice = .reasonRequired
            return false
        }
        return true
    }

    @discardableResult
    func submit(partnerUserID: UUID) async -> Bool {
        guard !isSubmitting, let service else {
            if service == nil {
                notice = .submitFailed
            }
            return false
        }
        guard let selectedReason else {
            notice = .reasonRequired
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let submission = preparedSubmission(
            partnerUserID: partnerUserID,
            reason: selectedReason
        )

        do {
            _ = try await service.submitConductReportAndLeave(
                partnerUserID: partnerUserID,
                reason: selectedReason,
                note: submission.fingerprint.note,
                blockPartner: blockPartner,
                operation: submission.operation
            )
            pendingSubmission = nil
            notice = .submitted
            return true
        } catch is CancellationError {
            return false
        } catch {
            notice = .submitFailed
            return false
        }
    }

    func dismissNotice() {
        notice = nil
    }

    private func preparedSubmission(
        partnerUserID: UUID,
        reason: PrivacyReportReason
    ) -> PendingSubmission {
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let fingerprint = SubmissionFingerprint(
            partnerUserID: partnerUserID,
            reason: reason,
            note: normalizedNote.isEmpty ? nil : normalizedNote,
            blockPartner: blockPartner
        )
        if let pendingSubmission, pendingSubmission.fingerprint == fingerprint {
            return pendingSubmission
        }

        let submission = PendingSubmission(
            fingerprint: fingerprint,
            operation: operationProvider.makeOperation()
        )
        pendingSubmission = submission
        return submission
    }
}

private extension ReportAndLeaveViewModel {
    struct SubmissionFingerprint: Equatable {
        let partnerUserID: UUID
        let reason: PrivacyReportReason
        let note: String?
        let blockPartner: Bool
    }

    struct PendingSubmission {
        let fingerprint: SubmissionFingerprint
        let operation: SyncClientOperation
    }
}
