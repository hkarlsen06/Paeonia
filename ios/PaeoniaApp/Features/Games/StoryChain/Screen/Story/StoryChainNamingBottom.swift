import SwiftUI

/// Under the whole story, the person who did not write the last line gives it a
/// title: a flower, a short line that says why, and a centered serif field with
/// a counter. "Name the story" is pinned in `StoryChainStoryView`.
struct StoryChainNamingBottom: View {
    @Bindable var viewModel: StoryChainViewModel
    /// The reveal has started and this part is fading out, so it takes no input.
    var isLeaving = false

    @FocusState private var isFocused: Bool
    @State private var ruleColor = Color.paeoniaSurfacePressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let titleFont = Font.system(.title2, design: .serif, weight: .regular)

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            StoryChainOrnament(isShown: true)
            Text(.storyChainNamePrompt(viewModel.partnerName))
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            titleField
            counter
        }
        .frame(maxWidth: .infinity)
        .disabled(isLeaving)
        .allowsHitTesting(!isLeaving)
        .accessibilityHidden(isLeaving)
        .onChange(of: isFocused) { _, focused in
            withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) {
                ruleColor = focused ? .paeoniaAccentPrimary : .paeoniaSurfacePressed
            }
        }
    }

    private var titleField: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            TextField(
                text: $viewModel.titleDraft,
                prompt: Text(.storyChainNamePlaceholder).foregroundStyle(.paeoniaTextTertiary),
                axis: .vertical
            ) {
                Text(.storyChainNamePlaceholder)
            }
            .textFieldStyle(.plain)
            .font(Self.titleFont)
            .multilineTextAlignment(.center)
            .foregroundStyle(.paeoniaTextPrimary)
            .tint(.paeoniaAccentPrimary)
            .lineLimit(1...3)
            .submitLabel(.done)
            .focused($isFocused)
            // A vertical field takes Return as a new line. A title is one line,
            // so Return puts the keyboard away instead.
            .onChange(of: viewModel.titleDraft) { _, draft in
                guard draft.contains(where: \.isNewline) else { return }
                viewModel.titleDraft = draft.filter { !$0.isNewline }
                isFocused = false
            }
            .accessibilityIdentifier("storyChain.titleField")

            Rectangle()
                .fill(ruleColor)
                .frame(height: PaeoniaRadius.strokeDefault)
                .accessibilityHidden(true)
        }
    }

    private var counter: some View {
        let length = StoryChainRules.length(viewModel.titleDraft)
        let limit = StoryChainRules.maxTitleLength
        return Text(verbatim: "\(length)/\(limit)")
            .font(PaeoniaTypography.caption.monospacedDigit())
            .foregroundStyle(length > limit ? .paeoniaErrorText : .paeoniaTextTertiary)
            .accessibilityLabel(Text(.storyChainWriteCountA11Y(length, limit)))
    }
}
