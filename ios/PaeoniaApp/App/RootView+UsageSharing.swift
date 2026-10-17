import SwiftUI

/// Who usage statistics count, and when the root asks "Help us improve Paeonia?".
/// `UsageSharingModel` keeps the answer.
extension RootView {
    /// Usage statistics count only the paired app, where Privacy and safety has
    /// the switch to stop them. Read from the screen shown rather than from
    /// session changes, because a session that ended while the app was closed
    /// never shows up as a change.
    var usageSharingUserID: String? {
        viewModel.state == .paired ? viewModel.currentSession?.id : nil
    }

    /// `offerPrimersAfterSharing` opens the question like a primer: after the
    /// person has shared something, and only on a visit with no other prompt.
    /// It closes once answered, or when the paired surface goes away.
    var usageSharingQuestionBinding: Binding<Bool> {
        Binding(
            get: {
                isUsageQuestionPresented
                    && usageSharing.needsAnswer
                    && stablePairedLocationIdentity != nil
            },
            // The sheet cannot be swiped away, so only the system closes it,
            // and the question stays unanswered for a later visit.
            set: { isPresented in
                if !isPresented {
                    isUsageQuestionPresented = false
                }
            }
        )
    }
}
