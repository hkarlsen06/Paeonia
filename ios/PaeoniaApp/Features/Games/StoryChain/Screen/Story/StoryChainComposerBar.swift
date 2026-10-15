import SwiftUI

/// The bar above the keyboard while the person writes: the word to give, the
/// last-line switch from line 8, the character counter from 200, and Send. It
/// rides up with the keyboard, like a chat composer.
struct StoryChainComposerBar: View {
    @Bindable var viewModel: StoryChainViewModel
    let openDareSheet: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            if viewModel.canEndHere {
                lastLineSwitch
            }
            controls
        }
        .padding(.vertical, PaeoniaSpacing.space8)
        .paeoniaReadableWidth(StoryChainPageStyle.measure)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .background(.paeoniaBackgroundSecondary)
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                dareControl
                HStack(spacing: PaeoniaSpacing.space8) {
                    counter
                    Spacer(minLength: 0)
                    StoryChainSendButton(viewModel: viewModel)
                }
            }
        } else {
            HStack(spacing: PaeoniaSpacing.space8) {
                dareControl
                    .layoutPriority(1)
                Spacer(minLength: 0)
                counter
                StoryChainSendButton(viewModel: viewModel)
            }
        }
    }

    // MARK: The word to give

    @ViewBuilder
    private var dareControl: some View {
        if viewModel.canGiveDare {
            if let dare = viewModel.dareToGive {
                dareChip(dare)
            } else {
                giveWordButton
            }
        }
    }

    /// An empty slot in the shape of the chip it turns into: a dashed gold
    /// outline with a plus, so it reads as something to tap.
    private var giveWordButton: some View {
        Button {
            openDareSheet()
        } label: {
            Label {
                Text(.storyChainWriteGiveWord(viewModel.partnerName))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: "plus")
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .background(Capsule(style: .continuous).fill(.paeoniaSurfaceSecondary))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.paeoniaInkGold,
                        style: StrokeStyle(lineWidth: PaeoniaRadius.strokeEmphasis, dash: [4, 3])
                    )
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("storyChain.giveWord")
    }

    private func dareChip(_ dare: StoryChainDare) -> some View {
        HStack(spacing: 0) {
            dareChipLabel(dare)
            dareRemoveButton
        }
        .background(Capsule(style: .continuous).fill(.paeoniaSurfaceSecondary))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.paeoniaInkGold, lineWidth: PaeoniaRadius.strokeEmphasis)
        }
    }

    /// Tapping the word opens the sheet again, to pick another.
    private func dareChipLabel(_ dare: StoryChainDare) -> some View {
        Button {
            openDareSheet()
        } label: {
            Text(.storyChainWriteDareChip(viewModel.partnerName, dare.word.uppercased()))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .minimumScaleFactor(0.8)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .padding(.leading, PaeoniaSpacing.space12)
                .padding(.vertical, PaeoniaSpacing.space8)
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("storyChain.dareChip")
    }

    private var dareRemoveButton: some View {
        Button {
            PaeoniaHaptics.selection()
            GameSound.tap.play(volume: 0.6)
            viewModel.removeDare()
        } label: {
            Image(systemName: "xmark")
                .font(PaeoniaTypography.caption.weight(.bold))
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.storyChainWriteDareRemoveA11Y))
        .accessibilityIdentifier("storyChain.dareRemove")
    }

    // MARK: Last line

    private var lastLineSwitch: some View {
        let isOn = Binding(
            get: { viewModel.isLastLine },
            set: { newValue in
                PaeoniaHaptics.selection()
                GameSound.tap.play(volume: 0.6)
                viewModel.isLastLine = newValue
            }
        )
        return Toggle(isOn: isOn) {
            Text(.storyChainWriteLastLine)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextPrimary)
        }
        .tint(.paeoniaAccentPrimary)
        // Line 20 always ends the story, so the switch is on and locked.
        .disabled(viewModel.mustEndHere)
        .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
        .accessibilityIdentifier("storyChain.lastLine")
    }

    // MARK: Counter

    @ViewBuilder
    private var counter: some View {
        let check = viewModel.lineCheck
        if check.showsCounter {
            Text(verbatim: "\(check.length.formatted())/\(StoryChainRules.maxLineLength.formatted())")
                .font(PaeoniaTypography.caption.monospacedDigit())
                .foregroundStyle(check.isTooLong ? .paeoniaErrorText : .paeoniaTextTertiary)
                .accessibilityLabel(Text(.storyChainWriteCountA11Y(check.length, StoryChainRules.maxLineLength)))
        }
    }
}

/// The round Send button. The circle is 36 points and the tap area 44.
struct StoryChainSendButton: View {
    let viewModel: StoryChainViewModel

    private var canSend: Bool { viewModel.lineCheck.canSend }

    var body: some View {
        Button {
            Task { await viewModel.sendLine() }
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(canSend ? Color.paeoniaTextInverse : Color.paeoniaTextTertiary)
                .frame(width: 36, height: 36)
                .background(canSend ? Color.paeoniaAccentPrimary : Color.paeoniaSurfaceDisabled, in: Circle())
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Circle())
        }
        .buttonStyle(StoryChainSendButtonStyle())
        .disabled(!canSend)
        .accessibilityLabel(Text(.storyChainWriteSendA11Y(viewModel.partnerName)))
        .accessibilityIdentifier("storyChain.send")
    }
}

private struct StoryChainSendButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(PaeoniaMotion.buttonPress, value: configuration.isPressed)
    }
}
