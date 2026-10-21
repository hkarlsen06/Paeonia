import Foundation

extension PrivacyRequestKind {
    var title: LocalizedStringResource {
        switch self {
        case .correction:
            .privacySafetyCorrectionTitle
        }
    }

    var description: LocalizedStringResource {
        switch self {
        case .correction:
            .privacySafetyCorrectionDescription
        }
    }

    var actionTitle: LocalizedStringResource {
        switch self {
        case .correction:
            .privacySafetyCorrectionAction
        }
    }
}

extension PrivacyRequestStatus {
    var title: LocalizedStringResource {
        switch self {
        case .submitted:
            .privacySafetyStatusSubmitted
        case .verifying:
            .privacySafetyStatusVerifying
        case .processing:
            .privacySafetyStatusProcessing
        case .completed:
            .privacySafetyStatusCompleted
        case .rejected:
            .privacySafetyStatusRejected
        case .cancelled:
            .privacySafetyStatusCancelled
        }
    }
}

extension PrivacyReportReason {
    var title: LocalizedStringResource {
        switch self {
        case .harassment:
            .reportAndLeaveReasonHarassment
        case .abuse:
            .reportAndLeaveReasonAbuse
        case .threat:
            .reportAndLeaveReasonThreat
        case .sexualContent:
            .reportAndLeaveReasonSexualContent
        case .hate:
            .reportAndLeaveReasonHate
        case .privacy:
            .reportAndLeaveReasonPrivacy
        case .impersonation:
            .reportAndLeaveReasonImpersonation
        case .selfHarm:
            .reportAndLeaveReasonSelfHarm
        case .spam:
            .reportAndLeaveReasonSpam
        case .other:
            .reportAndLeaveReasonOther
        }
    }
}
