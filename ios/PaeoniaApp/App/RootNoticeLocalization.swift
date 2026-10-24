import Foundation

/// Maps each root-level notice to its localized banner copy. Kept beside the
/// root coordinator but in its own file so `RootView` stays focused on view
/// logic.
extension RootNotice {
    /// Being signed out and an account that was not deleted are worth reading in full.
    var bannerTiming: PaeoniaBannerTiming {
        switch self {
        case .sessionEnded, .deleteAccountFailed:
            .untilDismissed
        default:
            .standard
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .sessionLoadFailed:
            .authNoticeSessionLoadFailedTitle
        case .sessionEnded:
            .authNoticeSessionEndedTitle
        case .signInFailed:
            .authNoticeSignInFailedTitle
        case .onboardingFailed:
            .authNoticeOnboardingFailedTitle
        case .signOutFailed:
            .authNoticeSignOutFailedTitle
        case .deleteAccountFailed:
            .authNoticeDeleteAccountFailedTitle
        case .relationshipEndedAcknowledgeFailed:
            .authNoticeRelationshipEndedAcknowledgeFailedTitle
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .sessionLoadFailed:
            .authNoticeSessionLoadFailedMessage
        case .sessionEnded:
            .authNoticeSessionEndedMessage
        case let .signInFailed(failure):
            failure == .offline ? .authNoticeSignInFailedMessage : .commonActionFailedMessage
        case .onboardingFailed:
            .authNoticeOnboardingFailedMessage
        case .signOutFailed:
            .authNoticeSignOutFailedMessage
        case let .deleteAccountFailed(failure):
            failure == .offline ? .authNoticeDeleteAccountFailedMessage : .commonActionFailedMessage
        case let .relationshipEndedAcknowledgeFailed(failure):
            failure == .offline ? .authNoticeRelationshipEndedAcknowledgeFailedMessage : .commonActionFailedMessage
        }
    }
}
