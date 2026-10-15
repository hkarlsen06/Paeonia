import SwiftUI

/// The short states before the first turn: loading, setup not done yet, and the
/// game being created.
struct ExquisiteCorpseStatusView: View {
    let viewModel: ExquisiteCorpseViewModel

    var body: some View {
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space16) {
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .needsSetup:
            PaeoniaEmptyStateView(
                title: .exquisiteCorpseName,
                message: .gamesNeedsSetup,
                systemImage: "gamecontroller.fill"
            )
        case .preparing where viewModel.startFailure != nil:
            PaeoniaLoadFailureView(
                failure: viewModel.startFailure ?? .other,
                offlineTitle: .gamesNoticeStartFailedTitle,
                offlineMessage: .gamesNoticeStartFailedMessage,
                failedMessage: .commonActionFailedMessage
            ) {
                Button {
                    Task { await viewModel.retryStart() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
        case .preparing:
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .controlSize(.large)
        default:
            // The first read is a split second. The screen stays blank.
            EmptyView()
        }
    }
}
