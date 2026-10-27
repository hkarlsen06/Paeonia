import SwiftUI

/// What sits under the story while the partner has the turn: one line of status
/// and, when the partner is away, a hint that a push will come. The partner's
/// live letters show in the page itself.
struct StoryChainWaitingBottom: View {
    let viewModel: StoryChainViewModel
    /// The story is finished and waits for a title, instead of for a line.
    let isNaming: Bool

    private var presence: StoryChainPartnerPresence { viewModel.partnerPresence }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            StoryChainPartnerLine(
                participants: viewModel.participants,
                text: statusText,
                isHere: presence.isHere,
                showsRing: presence.isHere,
                showsDots: showsDots,
                font: PaeoniaTypography.body.weight(.semibold)
            )
            if showsHint {
                Text(.storyChainWaitHint)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, PaeoniaSpacing.space4)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(PaeoniaMotion.stateChange, value: presence)
        .accessibilityIdentifier("storyChain.waiting")
    }

    /// Dots show while the partner is live on the screen that matches the wait.
    private var showsDots: Bool {
        isNaming ? presence == .choosing : presence == .writing
    }

    /// The hint is about the partner's line. A story that waits for a title has
    /// no turn to wait for.
    private var showsHint: Bool {
        !isNaming && presence == .away
    }

    private var statusText: LocalizedStringResource {
        let name = viewModel.partnerName
        if isNaming {
            return .storyChainWaitNaming(name)
        }
        switch presence {
        case .writing:
            return viewModel.partnerIsWritingLast ? .storyChainWaitWritingLast(name) : .storyChainWaitWriting(name)
        case .away:
            return .storyChainWaitGeneric(name)
        case .here, .reading, .choosing, .result:
            return .storyChainWriteHere(name)
        }
    }
}
