import Foundation
import Observation

@MainActor
@Observable
final class ReportAndLeaveViewModel {
    enum Notice: Equatable {
        case reasonRequired
        case submitFailed(PaeoniaFailure)
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
    /// True once the report went through. The relationship has ended by then, so
    /// the form stays locked and a second report cannot be filed.
    private(set) var didSubmit = false
    private(set) var notice: Notice?

    var isFormLocked: Bool {
        isSubmitting || didSubmit
    }

    var canSubmit: Bool {
        selectedReason != nil && !isFormLocked
    }

    init(
        service: (any PrivacySafetyServicing)? = PrivacySafetyServiceFactory.makeDefault(),
        operationProvider: (any SyncClientOperationProviding)? = nil
    ) {
        self.service = service
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
    }

    func prepareConfirmation() -> Bool {
        guard !isFormLocked else {
            return false
        }
        guard selectedReason != nil else {
            notice = .reasonRequired
            return false
        }
        return true
    }

    @discardableResult
    func submit(target: PrivacyReportTarget) async -> Bool {
        guard !isFormLocked else {
            return false
        }
        guard let service else {
            notice = .submitFailed(.other)
            return false
        }
        guard let selectedReason else {
            notice = .reasonRequired
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let submission = preparedSubmission(
            target: target,
            reason: selectedReason
        )

        do {
            _ = try await service.submitReportAndLeave(
                target: target,
                reason: selectedReason,
                note: submission.fingerprint.note,
                blockPartner: blockPartner,
                operation: submission.operation
            )
            pendingSubmission = nil
            didSubmit = true
            return true
        } catch is CancellationError {
            return false
        } catch {
            notice = .submitFailed(PaeoniaFailure(error))
            return false
        }
    }

    func dismissNotice() {
        notice = nil
    }

    private func preparedSubmission(
        target: PrivacyReportTarget,
        reason: PrivacyReportReason
    ) -> PendingSubmission {
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let fingerprint = SubmissionFingerprint(
            target: target,
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
        let target: PrivacyReportTarget
        let reason: PrivacyReportReason
        let note: String?
        let blockPartner: Bool
    }

    struct PendingSubmission {
        let fingerprint: SubmissionFingerprint
        let operation: SyncClientOperation
    }
}
