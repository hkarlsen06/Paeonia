import SwiftUI

/// The chat of a memory, a story or a game: the shared chat view, with the report flow behind
/// its long-press menu. A memory's chat follows the memory, so a note edited while it is open
/// shows at once.
struct ThreadChatScreen: View {
    enum Presentation {
        /// Pushed in the navigation stack of the screen that opens it.
        case pushed
        /// A sheet, with a navigation stack of its own and a close button in its bar.
        case sheet
        /// The panel under a game (`GameChatPanel`). It has no navigation bar, so the
        /// messages get the height, and its close button floats over them. It came up from
        /// below, so a swipe right does not close it.
        case panel
        /// Pulled in from the right edge over any tab (`CoupleChatSlideOver`), with a
        /// navigation stack of its own and a back button that slides it away again.
        case slideOver
    }

    let viewModel: ThreadChatViewModel
    var presentation = Presentation.pushed
    /// Opens the memory or story the chat is about from its header card.
    var onOpenHeader: (() -> Void)?
    var onClose: (() -> Void)?

    @Environment(\.threadChatContext) private var context
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var reportTarget: PrivacyReportTarget?

    var body: some View {
        switch presentation {
        case .pushed:
            chat
        case .sheet:
            NavigationStack {
                chat
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { closeButton }
                    }
            }
            // A sheet over the story covers the app's banner, so it shows its own.
            .paeoniaBanner(bannerCenter)
        case .panel:
            NavigationStack {
                chat
                    .toolbarVisibility(.hidden, for: .navigationBar)
                    .overlay(alignment: .topTrailing) {
                        closeButton
                            .font(PaeoniaTypography.caption.weight(.semibold))
                            .buttonStyle(PaeoniaGlassCircleButtonStyle())
                            .padding(PaeoniaSpacing.space4)
                    }
            }
            // The game's notices show over the messages, not over the shrunk game.
            .paeoniaBanner(bannerCenter)
        case .slideOver:
            NavigationStack {
                chat
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { backButton }
                    }
            }
            // It covers the tab bar's banner.
            .paeoniaBanner(bannerCenter)
        }
    }

    private var backButton: some View {
        Button {
            onClose?()
        } label: {
            Image(systemName: "chevron.backward")
        }
        .accessibilityLabel(Text(.commonBack))
        .accessibilityIdentifier("chat.slideOver.back")
    }

    private var closeButton: some View {
        Button {
            onClose?()
        } label: {
            Image(systemName: "xmark")
        }
        .accessibilityLabel(Text(.commonClose))
        .accessibilityIdentifier("chat.sheet.close")
    }

    private var chat: some View {
        ThreadChatView(
            viewModel: viewModel,
            participants: context.participants,
            onReport: { reportTarget = $0 },
            onClose: onClose,
            swipeRightCloses: presentation != .panel,
            onOpenHeader: onOpenHeader
        )
        .toolbar {
            // "Just us" calls the partner from its top bar.
            if viewModel.subject == .couple {
                ToolbarItem(placement: .topBarTrailing) { CallButton() }
            }
        }
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
