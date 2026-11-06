import SwiftUI

/// The Topics shelf: every topic as a tactile card, in the authored order, Flirt
/// last. The order never changes, so people find a topic where
/// they left it. Badges and the Topics card point at what's waiting.
struct TopicsShelfView: View {
    let viewModel: TopicsViewModel
    let onOpenTopic: (String) -> Void

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.vertical, PaeoniaSpacing.space16)
                .paeoniaReadableWidth()
        }
        .refreshable { await viewModel.refreshOverview() }
        .paeoniaTabBackdrop()
        .navigationTitle(Text(.topicsCardTitle))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
        .analyticsScreen("topics")
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasLoadedOverview, let failure = viewModel.overviewFailure {
            PaeoniaLoadFailureView(failure: failure, offlineMessage: .topicsNoticeOfflineMessage) {
                Button {
                    Task { await viewModel.refreshOverview() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
                .accessibilityIdentifier("topics.retryOverview")
            }
        } else if !viewModel.hasLoadedOverview {
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(maxWidth: .infinity)
        } else if viewModel.overview.isEmpty {
            PaeoniaEmptyStateView(
                title: .topicsShelfEmptyTitle,
                message: .topicsShelfEmptyMessage,
                systemImage: "books.vertical"
            )
        } else {
            TopicShelfGrid(
                topics: viewModel.overview,
                newQuestionCount: viewModel.newQuestionCount(for:),
                onOpenTopic: onOpenTopic
            )
        }
    }

    private func showBanner(for notice: TopicsViewModel.Notice?) {
        guard let notice else { return }
        bannerCenter.show(notice.banner)
        viewModel.dismissNotice()
    }
}

extension TopicsViewModel.Notice {
    /// Offline says to try again when online. Anything else says something went wrong,
    /// because the connection may be fine.
    var banner: PaeoniaBannerContent {
        let failure: PaeoniaFailure
        switch self {
        case let .loadFailed(value), let .skipFailed(value):
            failure = value
        }
        switch failure {
        case .offline:
            return .error(
                title: String(localized: .commonOfflineTitle),
                message: String(localized: .topicsNoticeOfflineMessage)
            )
        case .other:
            return .error(
                message: String(localized: .commonActionFailedMessage)
            )
        }
    }
}
