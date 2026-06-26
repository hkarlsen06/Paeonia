import Foundation

/// Maps each root-level notice to its localized banner copy. Kept beside the
/// root coordinator but in its own file so `RootView` stays focused on view
/// logic.
extension RootNotice {
    var title: LocalizedStringResource {
        switch self {
        case .sessionLoadFailed:
            .authNoticeSessionLoadFailedTitle
        case .signInFailed:
            .authNoticeSignInFailedTitle
        case .onboardingFailed:
            .authNoticeOnboardingFailedTitle
        case .signOutFailed:
            .authNoticeSignOutFailedTitle
        case .deleteAccountFailed:
            .authNoticeDeleteAccountFailedTitle
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .sessionLoadFailed:
            .authNoticeSessionLoadFailedMessage
        case .signInFailed:
            .authNoticeSignInFailedMessage
        case .onboardingFailed:
            .authNoticeOnboardingFailedMessage
        case .signOutFailed:
            .authNoticeSignOutFailedMessage
        case .deleteAccountFailed:
            .authNoticeDeleteAccountFailedMessage
        }
    }
}
