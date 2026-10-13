import SwiftUI

/// Waiting for the partner: they are picking a word, or drawing out of sight. It
/// says what is happening and makes the wait feel shared.
struct DrawAndGuessWaitingView: View {
    let viewModel: DrawAndGuessViewModel
    /// Fixed when the screen opens. The screen fades out when the drawing starts
    /// and must not change its words on the way.
    private let isDrawing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: DrawAndGuessViewModel) {
        self.viewModel = viewModel
        isDrawing = viewModel.phase == .waitingForDrawing
    }

    var body: some View {
        DrawAndGuessFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space24) {
                VStack(spacing: PaeoniaSpacing.space12) {
                    DrawAndGuessScoreHeader(viewModel: viewModel)
                    DrawAndGuessPendingSaveRow(viewModel: viewModel)
                }
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
                        }
                    }
                    .multilineTextAlignment(.center)
                    if isDrawing, viewModel.slots.slots.contains(where: { !$0.isGap }) {
                        dimSlots
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("draw.waiting")
                Spacer(minLength: PaeoniaSpacing.space16)
            }
            .frame(maxWidth: .infinity)
        } bottom: {
            DrawAndGuessInviteButton(viewModel: viewModel)
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

    // MARK: Avatar

    private var avatar: some View {
        DrawAndGuessAvatar(player: viewModel.partner, isMe: false, size: 96)
            .background {
                if viewModel.partnerPresence.isHere {
                    ring
                }
            }
            .padding(PaeoniaSpacing.space8)
    }

    /// A soft ring that breathes while the partner is in the room.
    @ViewBuilder
    private var ring: some View {
        let circle = Circle()
            .stroke(.paeoniaAccentPrimary, lineWidth: 4)
            .padding(-PaeoniaSpacing.space8)
            .blur(radius: 1.5)
            .accessibilityHidden(true)
        if reduceMotion {
            circle.opacity(0.35)
        } else {
            circle.phaseAnimator([0.2, 0.5]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 2.4)
            }
        }
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
/// game, reads "Sent" after a send, and comes back 15 minutes after the last invite.
struct DrawAndGuessInviteButton: View {
    let viewModel: DrawAndGuessViewModel

    var body: some View {
        switch viewModel.invite {
        case .hidden:
            EmptyView()
        case .available:
            sendButton
        case let .sent(until):
            // One tick at the moment the button comes back, so nothing polls.
            TimelineView(.explicit([until])) { context in
                if context.date >= until {
                    sendButton
                } else {
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
                }
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
