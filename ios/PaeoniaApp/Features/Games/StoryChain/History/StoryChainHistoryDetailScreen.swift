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

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .favoriteToolbarItem(
                .storyChainStory(storyID),
                isShown: isLoaded,
                identifier: "storyChain.history.star"
            )
            .task { await loadStory() }
            .accessibilityIdentifier("storyChain.history.detail")
    }

    private var isLoaded: Bool {
        if case .loaded = load { return true }
        return false
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
                content: content,
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
        .paeoniaShareToolbar(shareable, identifier: "storyChain.history.share")
        .gameConversationToolbar(.storyChain(story.id), result: .storyChain(story))
    }

    private var content: StoryChainPageContent {
        story.pageContent(
            currentUserID: history.currentUserID,
            youName: String(localized: .storyChainPageYou),
            partnerName: history.partnerName
        )
    }

    private var shareable: PaeoniaShareable? {
        guard let title = story.title else { return nil }
        return StoryChainShare.shareable(title: title, number: story.storyNumber, content: content)
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
            Text(.favoritesPrivacyHint)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, PaeoniaSpacing.space8)
        }
        .frame(maxWidth: .infinity)
    }
}
