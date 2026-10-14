import SwiftUI

/// "Give [Name] a word": three words Paeonia suggests, or a word of your own.
/// Picking a word closes the sheet. The partner's next line has to use it.
struct StoryChainDareSheet: View {
    @Bindable var viewModel: StoryChainViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var ownWord = ""
    @State private var showsError = false
    @State private var detent = PresentationDetent.medium
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                heading
                VStack(spacing: PaeoniaSpacing.space12) {
                    ForEach(viewModel.wordChoices) { choice in
                        StoryChainDareWordRow(
                            word: choice.word,
                            isSelected: viewModel.dareToGive?.wordID == choice.wordID
                        ) {
                            PaeoniaHaptics.selection()
                            viewModel.giveDare(choice)
                            dismiss()
                        }
                    }
                }
                ownWordSection
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space32)
            .padding(.bottom, PaeoniaSpacing.space16)
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: isFieldFocused) { _, focused in
            // The keyboard needs the room of the large sheet.
            if focused { detent = .large }
        }
        .accessibilityIdentifier("storyChain.dareSheet")
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(.storyChainDareTitle(viewModel.partnerName))
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(.storyChainDareSubtitle)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
    }

    // MARK: Own word

    private var ownWordSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.storyChainDareOwn)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
                .accessibilityAddTraits(.isHeader)
            ownWordField
            if showsError {
                Label {
                    Text(.storyChainDareOwnError)
                } icon: {
                    Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                }
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaErrorText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PaeoniaSpacing.space4)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: showsError)
    }

    private var ownWordField: some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
        // At the largest text sizes the button goes under the field, so the field keeps its width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space8))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space8))
        return layout {
            TextField(text: $ownWord) {
                Text(.storyChainDareOwnPlaceholder)
            }
            .font(PaeoniaTypography.title)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($isFieldFocused)
            .onSubmit(submitOwnWord)
            .accessibilityIdentifier("storyChain.dareField")

            Button(action: submitOwnWord) {
                Text(.storyChainDareOwnAction)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .disabled(ownWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("storyChain.dareOwnAction")
        }
        .padding(.leading, PaeoniaSpacing.cardContentPadding)
        .padding(.trailing, PaeoniaSpacing.space4)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? PaeoniaSpacing.space8 : 0)
        .frame(minHeight: 64)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                isFieldFocused ? .paeoniaAccentPrimary : .clear,
                lineWidth: PaeoniaRadius.strokeEmphasis
            )
        }
        .onChange(of: ownWord) { _, _ in showsError = false }
    }

    private func submitOwnWord() {
        guard !ownWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if viewModel.giveOwnDare(ownWord) {
            PaeoniaHaptics.selection()
            dismiss()
        } else {
            showsError = true
            PaeoniaHaptics.validationError()
            AccessibilityNotification.Announcement(String(localized: .storyChainDareOwnError)).post()
        }
    }
}

/// One of the three suggested words, in capitals as it will read in the chip.
struct StoryChainDareWordRow: View {
    let word: String
    let isSelected: Bool
    let action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaeoniaSpacing.space12) {
                Text(verbatim: word.uppercased())
                    .font(PaeoniaTypography.title)
                    .tracking(1)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .accessibilityHidden(true)
                }
            }
            .padding(PaeoniaSpacing.cardContentPadding)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(.paeoniaSurfaceSecondary)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? .paeoniaAccentPrimary : .clear,
                    lineWidth: PaeoniaRadius.strokeEmphasis
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: word))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("storyChain.dareWord.\(word)")
    }
}
