import SwiftUI

/// Opens one finished story from "Our stories". It reads the story from the
/// cache or the server, then shows it as the finished page.
struct StoryChainHistoryDetailHost: View {
    let history: StoryChainHistoryViewModel
    let storyID: UUID

    private enum Load {
        case loading
        case loaded(RemoteStoryChainStory)
        case failed(PaeoniaFailure)
    }

    @State private var load = Load.loading
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                if case .loaded = load {
                    ToolbarItem(placement: .topBarTrailing) {
                        StoryChainStarButton(
                            stars: history.stars,
                            storyID: storyID,
                            identifier: "storyChain.history.star"
                        )
                    }
                }
            }
            .task { await loadStory() }
            .onChange(of: history.stars.notice) { _, notice in
                guard let notice else { return }
                bannerCenter.show(notice.banner)
                history.stars.clearNotice()
            }
            .accessibilityIdentifier("storyChain.history.detail")
    }

    @ViewBuilder
    private var content: some View {
        switch load {
        case .loading:
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .controlSize(.large)
        case let .loaded(story):
            StoryChainHistoryDetailScreen(story: story, history: history)
        case let .failed(failure):
            PaeoniaLoadFailureView(
                failure: failure,
                offlineTitle: .storyChainOfflineTitle,
                offlineMessage: .storyChainHistoryOfflineMessage,
                failedMessage: .storyChainHistoryStoryFailedMessage
            ) {
                Button {
                    Task { await loadStory() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
                .accessibilityIdentifier("storyChain.history.retry")
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        }
    }

    private func loadStory() async {
        if case .failed = load {
            load = .loading
        }
        do {
            if let story = try await history.loadStory(id: storyID) {
                load = .loaded(story)
            } else if !Task.isCancelled {
                // The couple has no such story, which no connection would fix.
                load = .failed(.other)
            }
        } catch {
            if !Task.isCancelled {
                load = .failed(PaeoniaFailure(error))
            }
        }
    }
}

/// A finished story without the reveal: the title, the byline, the whole text,
/// the flower, how long it is, and a note that stars are private. The star is in
/// the toolbar.
struct StoryChainHistoryDetailScreen: View {
    let story: RemoteStoryChainStory
    let history: StoryChainHistoryViewModel

    var body: some View {
        ScrollView {
            StoryChainPageView(
                content: story.pageContent(
                    currentUserID: history.currentUserID,
                    youName: String(localized: .storyChainPageYou),
                    partnerName: history.partnerName
                ),
                eyebrow: Text(.storyChainStoryNumber(story.storyNumber)),
                title: story.title,
                byline: byline,
                youLabel: String(localized: .storyChainPageYou),
                openingLabel: String(localized: .storyChainPageOpening),
                lineInfo: { line in lineInfo(for: line) },
                trailing: { ending }
            )
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var byline: Text? {
        story.finishedAt.map { finishedAt in
            let date = finishedAt.formatted(.dateTime.month(.abbreviated).day())
            return Text(.storyChainFinishedByline(history.partnerName, date))
        }
    }

    private func lineInfo(for line: StoryChainPageLine) -> some View {
        StoryChainLineInfoPopover(
            name: line.authorName,
            isMine: line.isMine,
            mediaAssetID: nil,
            createdAt: line.createdAt,
            usedDare: line.usedDare
        )
    }

    private var ending: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            StoryChainOrnament(isShown: true)
            StoryChainStatsLine(lineCount: story.lines.count, dareCount: story.usedDareCount)
            ReactionSection(target: .storyChainStory(story.id), alignment: .center)
            Text(.storyChainStarPrivacy)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, PaeoniaSpacing.space8)
        }
        .frame(maxWidth: .infinity)
    }
}
