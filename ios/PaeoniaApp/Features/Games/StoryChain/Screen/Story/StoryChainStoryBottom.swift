import SwiftUI

/// The part of the page under the text, which changes with the phase: the
/// writer's field, the waiting status, the title field, or the end of a
/// finished story. The offline line sits last in every phase.
///
/// The slot holds one of the first three. When the story finishes, the slot keeps
/// the bottom the person had until the reveal scrolls to the top, so the page
/// does not jump. Then it fades out and the end of the story takes over.
struct StoryChainStoryBottom: View {
    let viewModel: StoryChainViewModel
    let reveal: StoryChainRevealTimeline
    /// The bottom a finished story fades out. Nil when there is nothing to fade.
    let departingPhase: StoryChainPhase?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            slot
            finishedEnd
            StoryChainOfflineLine(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The writer's field rises in when the partner's line has landed.
        .animation(reduceMotion ? PaeoniaMotion.stateChange : PaeoniaMotion.cardReveal, value: viewModel.bottomPhase)
        .animation(PaeoniaMotion.stateChange, value: viewModel.isHeldOnPhone)
    }

    private var rise: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12))
    }

    /// The composer starts to rise once the status row it replaces has mostly
    /// faded, so the two do not show through each other.
    private var composerRise: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: rise.animation(PaeoniaMotion.cardReveal.delay(0.12)),
            removal: rise
        )
    }

    /// The phase the slot shows. A finished story shows the bottom it replaces
    /// until the page has scrolled to the top.
    private var slotPhase: StoryChainPhase {
        guard case .finished = viewModel.phase else { return viewModel.bottomPhase }
        return reveal.scrolledToTop ? .loading : departingPhase ?? .loading
    }

    @ViewBuilder
    private var slot: some View {
        switch slotPhase {
        case .writing:
            StoryChainComposer(viewModel: viewModel)
                .transition(composerRise)
        case .waitingForLine:
            StoryChainWaitingBottom(viewModel: viewModel, isNaming: false)
                .transition(.opacity)
        case .waitingForName:
            StoryChainWaitingBottom(viewModel: viewModel, isNaming: true)
                .transition(.opacity)
                .accessibilityHidden(isFinished)
        case .naming:
            StoryChainNamingBottom(viewModel: viewModel, isLeaving: isFinished)
                .transition(.opacity)
        case .loading, .needsSetup, .preparing, .chooseOpening, .waitingForOpening, .waitingToSync, .finished:
            EmptyView()
        }
    }

    private var isFinished: Bool {
        if case .finished = viewModel.phase { return true }
        return false
    }

    @ViewBuilder
    private var finishedEnd: some View {
        if isFinished, let finished = viewModel.finished {
            StoryChainFinishedBottom(
                finished: finished,
                reveal: reveal,
                canReact: viewModel.story?.hasUnsentName == false,
                result: viewModel.story.map { .storyChain($0.story) }
            )
        }
    }
}
