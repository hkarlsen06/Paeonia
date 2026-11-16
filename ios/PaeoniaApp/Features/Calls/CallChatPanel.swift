import SwiftUI

/// "Just us" during a call. The call's window is a window of its own, so it doesn't get the app's
/// environment. The overlay reads the chat in the app's window when the call screen first asks for
/// it, and keeps what the chat needs from there, so it shows at once the next time.
struct CallChat {
    let coupleID: UUID
    let viewModel: ThreadChatViewModel
    let context: ThreadChatContext
    let banners: PaeoniaBannerCenter
    let reactions: ReactionStore?
    let mediaAlternativeEditing: MediaAlternativeEditingService?
}

extension View {
    /// What the chat reads from the environment in the app's window.
    func callChatEnvironment(_ chat: CallChat) -> some View {
        environment(\.threadChatContext, chat.context)
            .environment(chat.banners)
            .environment(chat.reactions)
            .environment(\.mediaAlternativeEditingService, chat.mediaAlternativeEditing)
    }
}

/// "Just us" as a panel under the call, the way a game's chat rises under the game
/// (`GameChatPanel`), while the call shrinks to a preview above it. It is the one place "Just us"
/// comes up from the bottom instead of in from the right. A drag down closes it, and so does a tap on
/// the call or the chat's close button, and the call grows back.
struct CallChatPanel: View {
    /// The share of the window's height the panel takes, as under a game.
    static let heightFraction: CGFloat = 0.64

    let chat: CallChat
    /// Up on screen, or below the bottom edge.
    let isRaised: Bool
    let height: CGFloat
    let close: () -> Void

    var body: some View {
        ChatPanelSurface(viewModel: chat.viewModel, close: close)
            .frame(height: height)
            .modifier(PanelSlide(offset: isRaised ? 0 : height))
            .frame(maxHeight: .infinity, alignment: .bottom)
            .callChatEnvironment(chat)
            // The keyboard opens inside the panel, so the call above it stays where it is.
            .ignoresSafeArea()
            .accessibilityIdentifier("calls.chat")
    }
}

/// While the panel is up, the call shows small above it: the big video, or the partner's face, name
/// and time. A tap on it closes the chat.
struct CallChatPreview: View {
    let session: CallSession
    let participants: DailyChallengeParticipants
    let showsIdentity: Bool
    let close: () -> Void

    private static let avatarSize: CGFloat = 64

    var body: some View {
        ZStack {
            if showsIdentity {
                VStack(spacing: PaeoniaSpacing.space8) {
                    PaeoniaCoupleAvatar(
                        mediaAssetID: participants.partnerProfilePhotoAssetID,
                        name: participants.partnerName,
                        tint: .paeoniaPartnerTwo,
                        size: Self.avatarSize,
                        isCurrentUser: false
                    )
                    .frame(width: Self.avatarSize, height: Self.avatarSize)
                    Text(verbatim: participants.partnerName)
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                    CallStatusLine(phase: session.phase, direction: session.direction, font: PaeoniaTypography.caption)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture(perform: close)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.callsChatBackToCall))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { close() }
        .accessibilityIdentifier("calls.chat.preview")
    }
}
