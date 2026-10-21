import SwiftUI

/// The chat of a memory or a story: the shared chat view, with the report flow behind its
/// long-press menu. Pushed in a navigation stack, or in a sheet with `embedsNavigationStack`,
/// which adds a stack of its own and a close button.
struct ThreadChatScreen: View {
    let viewModel: ThreadChatViewModel
    var embedsNavigationStack = false
    var onClose: (() -> Void)?

    @Environment(\.threadChatContext) private var context
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var reportTarget: PrivacyReportTarget?

    var body: some View {
        if embedsNavigationStack {
            NavigationStack {
                chat
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                onClose?()
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel(Text(.commonClose))
                        }
                    }
            }
            // A sheet over the story covers the app's banner, so it shows its own.
            .paeoniaTopBanner(bannerCenter)
        } else {
            chat
        }
    }

    private var chat: some View {
        ThreadChatView(
            viewModel: viewModel,
            participants: context.participants,
            onReport: { reportTarget = $0 },
            onClose: onClose
        )
        .navigationDestination(item: $reportTarget) { target in
            if let partnerUserID = context.participants.partnerUserID {
                ReportAndLeaveView(
                    partnerUserID: partnerUserID,
                    partnerName: context.participants.partnerName,
                    reportTarget: target,
                    service: context.reporting.service,
                    operationProvider: context.reporting.operationProvider,
                    onReportedAndLeft: context.reporting.onReportedAndLeft
                )
            }
        }
    }
}
