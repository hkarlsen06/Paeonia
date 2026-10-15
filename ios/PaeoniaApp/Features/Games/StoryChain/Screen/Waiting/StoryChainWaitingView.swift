import SwiftUI

/// Waiting for the partner to pick an opening and start the next story. It says
/// what is happening and makes the wait feel shared.
struct StoryChainWaitingView: View {
    let viewModel: StoryChainViewModel

    private var presence: StoryChainPartnerPresence { viewModel.partnerPresence }

    var body: some View {
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space24) {
                Spacer(minLength: PaeoniaSpacing.space16)
                VStack(spacing: PaeoniaSpacing.space16) {
                    avatar
                    VStack(spacing: PaeoniaSpacing.space8) {
                        Text(title)
                            .font(PaeoniaTypography.title)
                            .foregroundStyle(.paeoniaTextPrimary)
                        if presence == .away {
                            Text(.storyChainWaitHint)
                                .font(PaeoniaTypography.body)
                                .foregroundStyle(.paeoniaTextSecondary)
                                .transition(.opacity)
                        }
                    }
                    .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("storyChain.waitingForOpening")
                Spacer(minLength: PaeoniaSpacing.space16)
            }
            .frame(maxWidth: .infinity)
        }
        .gameInviteToolbar(
            invite: viewModel.invite,
            partnerName: viewModel.partnerName,
            send: viewModel.sendInvite,
            identifier: "storyChain.invite"
        )
        // The partner's phone changes the title, hint and ring while this screen
        // is open. Everything moves to its new place together.
        .animation(PaeoniaMotion.stateChange, value: presence)
    }

    private var title: LocalizedStringResource {
        let name = viewModel.partnerName
        return presence == .choosing ? .storyChainWaitOpening(name) : .storyChainWaitStartNext(name)
    }

    private var avatar: some View {
        StoryChainAvatar(participants: viewModel.participants, isMe: false, size: 96)
            .accessibilityHidden(true)
            .background { StoryChainBreathingRing(isActive: presence.isHere) }
            .padding(PaeoniaSpacing.space8)
    }
}
