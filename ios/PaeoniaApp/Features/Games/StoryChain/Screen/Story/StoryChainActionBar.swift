import SwiftUI

/// The buttons pinned under the story: "Name the story" while the person names
/// it, and the way on once the finished story has arrived. It is a bottom bar,
/// so the keyboard covers it instead of pushing it up.
struct StoryChainActionBar: View {
    let viewModel: StoryChainViewModel
    let reveal: StoryChainRevealTimeline

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            content
        }
        .padding(.vertical, hasContent ? PaeoniaSpacing.space8 : 0)
        .paeoniaReadableWidth(StoryChainPageStyle.measure)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .background(hasContent ? Color.paeoniaBackgroundSecondary : Color.clear)
        .animation(reduceMotion ? PaeoniaMotion.stateChange : PaeoniaMotion.cardReveal, value: viewModel.phase)
        .animation(reduceMotion ? PaeoniaMotion.stateChange : PaeoniaMotion.cardReveal, value: reveal.actionsShown)
    }

    private var hasContent: Bool {
        switch viewModel.phase {
        case .naming: true
        case .finished: reveal.actionsShown
        default: false
        }
    }

    private var rise: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .naming:
            Button {
                Task { await viewModel.nameStory() }
            } label: {
                Text(.storyChainNameAction)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(!viewModel.canName)
            .transition(rise)
            .accessibilityIdentifier("storyChain.name")
        case .finished:
            if reveal.actionsShown, let finished = viewModel.finished {
                continueButton(finished)
                    .transition(rise)
            }
        case .loading, .needsSetup, .preparing, .chooseOpening, .waitingForOpening, .waitingToSync, .writing,
             .waitingForLine, .waitingForName:
            EmptyView()
        }
    }

    private func continueButton(_ finished: StoryChainFinishedStory) -> some View {
        let title: LocalizedStringResource =
            finished.isNamer ? .storyChainFinishedStartNew : .storyChainFinishedContinue
        return Button {
            Task { await viewModel.continueFromFinished() }
        } label: {
            Text(title)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .accessibilityIdentifier("storyChain.continue")
    }
}
