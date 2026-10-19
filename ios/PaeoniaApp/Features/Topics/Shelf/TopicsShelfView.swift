import SwiftUI

/// The Topics shelf: every topic as a tactile card, in the authored order, Flirt
/// last. The order never changes, so people find a topic where
/// they left it. Badges and the Topics card point at what's waiting.
struct TopicsShelfView: View {
    let viewModel: TopicsViewModel
    let onOpenTopic: (String) -> Void

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: PaeoniaSpacing.space12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: PaeoniaSpacing.space12) {
                ForEach(viewModel.overview) { topic in
                    Button {
                        onOpenTopic(topic.id)
                    } label: {
                        TopicShelfCard(topic: topic, newCount: viewModel.newQuestionCount(for: topic.id))
                    }
                    .buttonStyle(.paeoniaPressableCard)
                    .accessibilityIdentifier("topics.card.\(topic.id)")
                }
            }
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
                title: String(localized: .commonLoadFailedTitle),
                message: String(localized: .commonActionFailedMessage)
            )
        }
    }
}
