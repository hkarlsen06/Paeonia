import SwiftUI

/// A screen that could not load, told honestly. Offline, it shows the screen's own
/// offline title and line. Otherwise it says something went wrong and doesn't
/// blame the connection, because the connection may be fine. That case also links
/// to support, since trying again later may not help.
struct PaeoniaLoadFailureView<Action: View>: View {
    private let failure: PaeoniaFailure
    private let offlineTitle: LocalizedStringResource
    private let offlineMessage: LocalizedStringResource
    private let failedMessage: LocalizedStringResource
    private let action: Action

    init(
        failure: PaeoniaFailure,
        offlineTitle: LocalizedStringResource = .commonOfflineTitle,
        offlineMessage: LocalizedStringResource,
        failedMessage: LocalizedStringResource = .commonLoadFailedMessage,
        @ViewBuilder action: () -> Action
    ) {
        self.failure = failure
        self.offlineTitle = offlineTitle
        self.offlineMessage = offlineMessage
        self.failedMessage = failedMessage
        self.action = action()
    }

    var body: some View {
        switch failure {
        case .offline:
            PaeoniaEmptyStateView(title: offlineTitle, message: offlineMessage, systemImage: "wifi.slash") {
                action
            }
        case .other:
            PaeoniaEmptyStateView(
                title: .commonLoadFailedTitle,
                message: failedMessage,
                systemImage: "exclamationmark.circle"
            ) {
                VStack(spacing: PaeoniaSpacing.space8) {
                    action
                    PaeoniaSupportLink()
                }
            }
        }
    }
}
