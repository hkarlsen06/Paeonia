import SwiftUI

/// The writer's part of the page: who is reading along, the word the partner
/// dared this person to use, and the field where the next line gets written. The
/// field is the last paragraph of the page, in the writer's own ink.
///
/// The controls that belong above the keyboard (the word to give, the last-line
/// switch, the counter and Send) are in `StoryChainComposerBar`.
struct StoryChainComposer: View {
    @Bindable var viewModel: StoryChainViewModel

    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .title3) private var fieldMinHeight: CGFloat = 96
    /// The rule under the field. It changes through `withAnimation`, because an
    /// `.animation(value:)` modifier here would also re-time the movement the
    /// keyboard causes (see `DailyAnswerTextField`).
    @State private var ruleColor = Color.paeoniaSurfacePressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            StoryChainPartnerLine(
                participants: viewModel.participants,
                text: liveText,
                showsRing: viewModel.partnerPresence == .reading
            )
            .animation(PaeoniaMotion.stateChange, value: viewModel.partnerPresence)
            if let dare = viewModel.dareForMe {
                StoryChainDareCapsule(word: dare, isUsed: viewModel.lineCheck.usesDare == true)
            }
            field
            if showsDareHint, let dare = viewModel.dareForMe {
                Text(.storyChainWriteMustUseHint(dare.uppercased()))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: showsDareHint)
        .onChange(of: isFocused) { _, focused in
            withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) {
                ruleColor = focused ? .paeoniaAccentPrimary : .paeoniaSurfacePressed
            }
        }
    }

    // MARK: Field

    private var field: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            TextField(
                text: $viewModel.draft,
                prompt: Text(prompt).foregroundStyle(.paeoniaTextTertiary),
                axis: .vertical
            ) {
                Text(prompt)
            }
            .textFieldStyle(.plain)
            .font(StoryChainPageStyle.bodyFont)
            .lineSpacing(StoryChainPageStyle.lineSpacing)
            .foregroundStyle(StoryChainPageStyle.mineInk)
            .tint(StoryChainPageStyle.mineInk)
            .focused($isFocused)
            .frame(maxWidth: .infinity, minHeight: fieldMinHeight, alignment: .topLeading)
            .background { tapArea }
            .accessibilityIdentifier("storyChain.composer")

            Rectangle()
                .fill(ruleColor)
                .frame(height: PaeoniaRadius.strokeDefault)
                .accessibilityHidden(true)
        }
    }

    /// The empty space under the text takes a tap too. VoiceOver goes to the field itself.
    private var tapArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityHidden(true)
    }

    private var prompt: LocalizedStringResource {
        if viewModel.isLastLine {
            return .storyChainWriteLastLinePrompt
        }
        if viewModel.nextLineNumber == 1, viewModel.page.opening == nil {
            return .storyChainWritePlaceholderFirst
        }
        return .storyChainWritePlaceholder
    }

    // MARK: Live row

    /// Always laid out, so the field does not move when the partner comes or goes.
    private var liveText: LocalizedStringResource {
        let name = viewModel.partnerName
        switch viewModel.partnerPresence {
        case .reading: return .storyChainWriteReadingAlong(name)
        case .away: return .storyChainWriteLater(name)
        case .here, .writing, .choosing, .result: return .storyChainWriteHere(name)
        }
    }

    // MARK: Dare hint

    /// The line is long enough to send, but it misses the dared word. Before that
    /// the capsule above the field says it already.
    private var showsDareHint: Bool {
        let check = viewModel.lineCheck
        return check.usesDare == false && !check.isTooShort && !check.isTooLong
    }
}

/// "Use the word LIGHTHOUSE" in a capsule with a gold outline. Its empty circle
/// turns into a green check once the draft contains the word.
struct StoryChainDareCapsule: View {
    let word: String
    let isUsed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label {
            Text(.storyChainWriteMustUse(word.uppercased()))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: isUsed ? "checkmark.circle.fill" : "circle")
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .foregroundStyle(isUsed ? .paeoniaSuccess : .paeoniaTextPrimary)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    isUsed ? Color.paeoniaSuccess : Color.paeoniaInkGold,
                    lineWidth: PaeoniaRadius.strokeEmphasis
                )
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: isUsed)
        .onChange(of: isUsed) { _, used in
            if used {
                PaeoniaHaptics.selection()
                GameSound.bonus.play(volume: 0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.storyChainWriteMustUse(word)))
        .accessibilityAddTraits(isUsed ? .isSelected : [])
        .accessibilityIdentifier("storyChain.dare")
    }
}
