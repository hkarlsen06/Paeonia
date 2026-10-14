import SwiftUI

/// Start a new story: pick one of three opening lines, or write the first line
/// yourself. The story starts when the person taps "Start writing", so picking a
/// row is only a selection.
struct StoryChainChooseOpeningView: View {
    @Bindable var viewModel: StoryChainViewModel

    /// The openings on screen. The screen keeps showing them while it fades out
    /// after the start, when the view model has already cleared its own list.
    @State private var shownChoices: [RemoteStoryOpening]
    @State private var isStarting = false
    /// The choice that was started, kept for the fade-out.
    @State private var startedChoice: StoryChainOpeningChoice?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: StoryChainViewModel) {
        self.viewModel = viewModel
        _shownChoices = State(initialValue: viewModel.openingChoices)
    }

    private var selection: StoryChainOpeningChoice? {
        isStarting ? startedChoice : viewModel.selectedOpening
    }

    var body: some View {
        StoryChainFocusedLayout {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                heading
                if viewModel.openingsUnavailable {
                    offline
                } else {
                    openings
                }
                StoryChainOwnLineRow(isSelected: selection == .own) {
                    select(.own)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } bottom: {
            Button {
                start()
            } label: {
                Text(.storyChainChooseStart)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: isStarting))
            .disabled(selection == nil)
            .accessibilityIdentifier("storyChain.start")
        }
        .onChange(of: viewModel.openingChoices) { _, new in
            if !new.isEmpty { shownChoices = new }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(.storyChainChooseTitle)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(.storyChainChooseSubtitle(viewModel.partnerName))
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
    }

    private var openings: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            ForEach(shownChoices) { opening in
                StoryChainOpeningRow(
                    text: opening.text,
                    isSelected: selection == .opening(opening),
                    identifier: "storyChain.opening.\(opening.openingID)"
                ) {
                    select(.opening(opening))
                }
            }
        }
    }

    private var offline: some View {
        PaeoniaEmptyStateView(
            title: .storyChainOfflineTitle,
            message: .storyChainChooseOfflineMessage,
            systemImage: "wifi.slash"
        ) {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Text(.commonTryAgain)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .accessibilityIdentifier("storyChain.retryOpenings")
        }
    }

    private func select(_ choice: StoryChainOpeningChoice) {
        guard !isStarting else { return }
        PaeoniaHaptics.selection()
        withAnimation(reduceMotion ? nil : PaeoniaMotion.buttonPress) {
            viewModel.selectedOpening = choice
        }
    }

    private func start() {
        guard !isStarting, let choice = viewModel.selectedOpening else { return }
        isStarting = true
        startedChoice = choice
        Task {
            await viewModel.startStory()
            isStarting = false
        }
    }
}
