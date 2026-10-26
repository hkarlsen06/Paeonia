import SwiftUI

/// The chat of a memory or a story: the shared chat view, with the report flow behind its
/// long-press menu. Pushed in a navigation stack, or in a sheet with `embedsNavigationStack`,
/// which adds a stack of its own and a close button. A memory's chat follows the memory, so
/// a note edited while it is open shows at once.
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
        // Here and not on the screen under the chat, which SwiftUI does not update while covered.
        .onChange(of: memoryHeader) { _, header in
            if let header { viewModel.header = header }
        }
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

    /// The header of a memory's chat as the memories hold it now. Nil for any other chat.
    private var memoryHeader: ThreadChatHeader? {
        guard viewModel.subject.kind == .memory,
              let record = context.memories?.record(for: viewModel.subject.id)
        else { return nil }
        return ThreadChatHeader(memory: record)
    }
}
