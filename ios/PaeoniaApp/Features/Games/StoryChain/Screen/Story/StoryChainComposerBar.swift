import SwiftUI

/// Optional writing controls and Send, pinned above the keyboard.
struct StoryChainComposerBar: View {
    @Bindable var viewModel: StoryChainViewModel
    let openDareSheet: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        controls
            .padding(.vertical, PaeoniaSpacing.space8)
            .paeoniaReadableWidth(StoryChainPageStyle.measure)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .background(.paeoniaBackgroundSecondary)
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            wrappedControls
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PaeoniaSpacing.space8) {
                    optionalControls
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    sendControls
                }
                wrappedControls
            }
        }
    }

    private var optionalControls: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            dareControl
            if viewModel.canEndHere { lastLineChip }
        }
    }

    private var wrappedControls: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            ViewThatFits(in: .horizontal) {
                optionalControls.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    dareControl
                    if viewModel.canEndHere { lastLineChip }
                }
            }
            HStack {
                Spacer(minLength: 0)
                sendControls
            }
        }
    }

    private var sendControls: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            counter
                .fixedSize()
            StoryChainSendButton(viewModel: viewModel)
        }
        .fixedSize()
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

    private var giveWordButton: some View {
        Button {
            openDareSheet()
        } label: {
            Label {
                Text(.storyChainWriteGiveWordShort)
                    .fixedSize(horizontal: false, vertical: true)
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
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.storyChainWriteGiveWord(viewModel.partnerName)))
        .accessibilityIdentifier("storyChain.giveWord")
    }

    private func dareChip(_ dare: StoryChainDare) -> some View {
        HStack(spacing: 0) {
            dareChipLabel(dare)
            dareRemoveButton
        }
        .background(Capsule(style: .continuous).fill(.paeoniaSurfaceSecondary))
    }

    /// Tapping the word opens the sheet again, to pick another.
    private func dareChipLabel(_ dare: StoryChainDare) -> some View {
        Button {
            openDareSheet()
        } label: {
            Text(verbatim: dare.word.uppercased())
                .fixedSize(horizontal: false, vertical: true)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .padding(.leading, PaeoniaSpacing.space12)
                .padding(.vertical, PaeoniaSpacing.space8)
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.storyChainWriteDareChip(viewModel.partnerName, dare.word.uppercased())))
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

    private var lastLineChip: some View {
        let isOn = Binding(
            get: { viewModel.isLastLine },
            set: { newValue in
                PaeoniaHaptics.selection()
                GameSound.tap.play(volume: 0.6)
                viewModel.isLastLine = newValue
            }
        )
        return Toggle(isOn: isOn) {
            Label {
                Text(.storyChainWriteLastLineShort)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: viewModel.isLastLine ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(viewModel.isLastLine ? Color.paeoniaAccentPrimary : Color.paeoniaTextPrimary)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .background(
                viewModel.isLastLine ? Color.paeoniaAccentPrimary.opacity(0.16) : Color.paeoniaSurfaceSecondary,
                in: Capsule(style: .continuous)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        // Line 20 always ends the story, so the chip is selected and locked.
        .disabled(viewModel.mustEndHere)
        .accessibilityLabel(Text(.storyChainWriteLastLine))
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

/// Sends the current line with the shared circular action style.
struct StoryChainSendButton: View {
    let viewModel: StoryChainViewModel

    var body: some View {
        Button {
            Task { await viewModel.sendLine() }
        } label: {
            Image(systemName: "arrow.up")
        }
        .buttonStyle(PaeoniaCircularButtonStyle())
        .disabled(!viewModel.lineCheck.canSend)
        .accessibilityLabel(Text(.storyChainWriteSendA11Y(viewModel.partnerName)))
        .accessibilityIdentifier("storyChain.send")
    }
}
