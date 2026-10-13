import SwiftUI

/// Waiting for the partner: they are picking a word, or drawing out of sight. It
/// says what is happening and makes the wait feel shared.
struct DrawAndGuessWaitingView: View {
    let viewModel: DrawAndGuessViewModel
    /// Fixed when the screen opens. The screen fades out when the drawing starts
    /// and must not change its words on the way.
    private let isDrawing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    init(viewModel: DrawAndGuessViewModel) {
        self.viewModel = viewModel
        isDrawing = viewModel.phase == .waitingForDrawing
    }

    var body: some View {
        DrawAndGuessFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space24) {
                DrawAndGuessScoreHeader(viewModel: viewModel)
                Spacer(minLength: PaeoniaSpacing.space16)
                VStack(spacing: PaeoniaSpacing.space16) {
                    avatar
                    VStack(spacing: PaeoniaSpacing.space8) {
                        Text(title)
                            .font(PaeoniaTypography.title)
                            .foregroundStyle(.paeoniaTextPrimary)
                        if let hint {
                            Text(hint)
                                .font(PaeoniaTypography.body)
                                .foregroundStyle(.paeoniaTextSecondary)
                                .transition(.opacity)
                        }
                    }
                    .multilineTextAlignment(.center)
                    if isDrawing, viewModel.slots.slots.contains(where: { !$0.isGap }) {
                        dimSlots
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("draw.waiting")
                reactionCapsule
                Spacer(minLength: PaeoniaSpacing.space16)
            }
            .frame(maxWidth: .infinity)
        } bottom: {
            DrawAndGuessInviteButton(viewModel: viewModel)
        }
        // The partner's phone changes the title, hint, ring, and invite button
        // while this screen is open. Everything moves to its new place together.
        .animation(PaeoniaMotion.stateChange, value: viewModel.partnerPresence)
        .animation(PaeoniaMotion.stateChange, value: viewModel.invite)
        .animation(reduceMotion ? nil : PaeoniaMotion.cardReveal, value: viewModel.reactionToMyLastDrawing)
        .onChange(of: viewModel.reactionToMyLastDrawing) { old, new in
            // The guesser reacted after this person left the result.
            guard let new, new != old, !isDrawing else { return }
            PaeoniaHaptics.partnerDrawingReceived()
            AccessibilityNotification.Announcement(
                String(localized: new.drawerLine(partnerName: viewModel.partnerName, word: viewModel.round?.word))
            ).post()
        }
        .drawAndGuessScoreToolbar(viewModel)
    }

    /// Says what the partner is doing when their phone has told us.
    private var title: LocalizedStringResource {
        let name = viewModel.partnerName
        if isDrawing {
            return .gamesDrawAndGuessWaitDrawing(name)
        }
        switch viewModel.partnerPresence {
        case .result: return .gamesDrawAndGuessWaitContinue(name)
        case .choosing: return .gamesDrawAndGuessWaitChoosing(name)
        case .away, .here, .watching, .drawing: return .gamesDrawAndGuessWaitGeneric(name)
        }
    }

    /// "You'll watch it happen" only fits a drawing that is coming. While the
    /// partner is still picking a word or looking at a result, the title says enough.
    private var hint: LocalizedStringResource? {
        if isDrawing {
            return viewModel.partnerPresence.isHere ? .gamesDrawAndGuessWaitHintLive : .gamesDrawAndGuessWaitHintLater
        }
        return viewModel.partnerPresence.isInRoom ? nil : .gamesDrawAndGuessWaitHintLater
    }

    /// The partner's reaction to the round this person just drew. The line names
    /// the word, because the drawing is not on this screen.
    @ViewBuilder
    private var reactionCapsule: some View {
        if !isDrawing, let reaction = viewModel.reactionToMyLastDrawing {
            DrawAndGuessReactionCapsule(
                reaction: reaction,
                partnerName: viewModel.partnerName,
                word: viewModel.round?.word
            )
            .multilineTextAlignment(.center)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    // MARK: Avatar

    private var avatar: some View {
        DrawAndGuessAvatar(player: viewModel.partner, isMe: false, size: 96)
            .background { ring }
            .padding(PaeoniaSpacing.space8)
    }

    /// A soft ring that breathes while the partner is in the room. It stays in the
    /// layout and fades in and out. The breathing animation covers only the
    /// ring's opacity, so the ring moves with the avatar when the layout changes.
    private var ring: some View {
        Circle()
            .stroke(.paeoniaAccentPrimary, lineWidth: 4)
            .padding(-PaeoniaSpacing.space8)
            .blur(radius: 1.5)
            .animation(reduceMotion ? nil : breathing) {
                $0.opacity(reduceMotion ? 0.35 : isBreathing ? 0.5 : 0.2)
            }
            .opacity(viewModel.partnerPresence.isHere ? 1 : 0)
            .onAppear { isBreathing = true }
            .accessibilityHidden(true)
    }

    private var breathing: Animation {
        PaeoniaMotion.standardCurve(duration: 2.4).repeatForever(autoreverses: true)
    }

    // MARK: Dim slots

    /// The answer's slots, dimmed. They leak nothing the guesser's phone does not
    /// already have, and they are the first hint that something is coming.
    private var dimSlots: some View {
        let letters = viewModel.slots.slots.count { !$0.isGap }
        return VStack(spacing: PaeoniaSpacing.space8) {
            DrawAndGuessFlowLayout(spacing: PaeoniaSpacing.space12, lineSpacing: PaeoniaSpacing.space8) {
                ForEach(wordLengths.indices, id: \.self) { index in
                    HStack(spacing: PaeoniaSpacing.space4) {
                        ForEach(0..<wordLengths[index], id: \.self) { _ in
                            RoundedRectangle(cornerRadius: PaeoniaRadius.radius8, style: .continuous)
                                .fill(.paeoniaSurfaceSecondary)
                                .frame(width: 26, height: 34)
                                .overlay(alignment: .bottom) {
                                    Capsule().fill(.paeoniaTextTertiary).frame(height: 2).padding(6)
                                }
                        }
                    }
                }
            }
            .opacity(0.6)
            .accessibilityHidden(true)
            Text(.gamesDrawAndGuessWaitLetters(letters))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
        }
    }

    /// Letters per group. A word longer than 10 letters splits into even groups,
    /// so the slots fit the narrowest phone.
    private var wordLengths: [Int] {
        var lengths = [0]
        for slot in viewModel.slots.slots {
            if slot.isGap { lengths.append(0) } else { lengths[lengths.count - 1] += 1 }
        }
        return lengths.filter { $0 > 0 }.flatMap { DrawAndGuessSlotSizing.split($0, maxCount: 10) }
    }
}

/// "Tell [Name] you want to play". It shows only while the partner is not in the
/// game, reads "Sent" after a send with the time the next one can go, and comes
/// back 15 minutes after the last invite. The view model's tick brings it back.
struct DrawAndGuessInviteButton: View {
    let viewModel: DrawAndGuessViewModel

    var body: some View {
        switch viewModel.invite {
        case .hidden:
            EmptyView()
        case .available:
            sendButton
        case let .sent(until):
            VStack(spacing: PaeoniaSpacing.space8) {
                Button {} label: {
                    Label {
                        Text(.gamesInviteSent)
                    } icon: {
                        Image(systemName: "checkmark").accessibilityHidden(true)
                    }
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
                .disabled(true)
                .accessibilityIdentifier("draw.invite.sent")
                Text(.gamesInviteSentUntil(until.formatted(date: .omitted, time: .shortened)))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var sendButton: some View {
        Button {
            Task { await viewModel.sendInvite() }
        } label: {
            Text(.gamesInviteButton(viewModel.partnerName))
        }
        .buttonStyle(PaeoniaSecondaryButtonStyle())
        .accessibilityIdentifier("draw.invite")
    }
}
