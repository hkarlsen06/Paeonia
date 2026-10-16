import SwiftUI

/// A thought bubble over a Home avatar with the person's note. Without a note, your own
/// bubble shows a quiet "Note..." that opens the editor.
struct StoryNoteBubble: View {
    /// Nil shows the placeholder.
    let text: String?

    private static let maxWidth: CGFloat = 116

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
            Group {
                if let text {
                    Text(text)
                        .foregroundStyle(.paeoniaTextPrimary)
                } else {
                    Text(.storiesNotePlaceholder)
                        .foregroundStyle(.paeoniaTextTertiary)
                }
            }
            .font(PaeoniaTypography.caption)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .background(
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                    .fill(.paeoniaSurfaceSecondary)
            )
            // The two small circles that make it a thought bubble.
            Circle()
                .fill(.paeoniaSurfaceSecondary)
                .frame(width: 8, height: 8)
                .padding(.leading, PaeoniaSpacing.space16)
            Circle()
                .fill(.paeoniaSurfaceSecondary)
                .frame(width: 4, height: 4)
                .padding(.leading, PaeoniaSpacing.space24)
        }
        .frame(maxWidth: Self.maxWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Writes, changes or removes your note. Your partner sees it over your avatar on Home
/// for a day. A failed save keeps the text here, and the error shows in the banner.
struct StoryNoteEditor: View {
    let viewModel: StoriesViewModel
    let partnerName: String
    /// The note on Home now, if any. The field starts with it.
    let current: StoryNote?

    @State private var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    init(viewModel: StoriesViewModel, partnerName: String, current: StoryNote?) {
        self.viewModel = viewModel
        self.partnerName = partnerName
        self.current = current
        _text = State(initialValue: current?.text ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                field
                hint
                Spacer(minLength: 0)
                buttons
            }
            .padding(PaeoniaSpacing.screenHorizontalPadding)
            .paeoniaScreenBackground()
            .navigationTitle(Text(.storiesNoteTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(.commonCancel)
                    }
                    .disabled(viewModel.isSavingNote)
                }
            }
        }
        // The sheet covers the app's top banner, so show it here too.
        .paeoniaTopBanner(bannerCenter)
        .presentationDetents([.medium])
        .presentationBackground(.paeoniaBackgroundPrimary)
        .interactiveDismissDisabled(viewModel.isSavingNote)
        .onAppear { isFocused = true }
    }

    private var field: some View {
        TextField(text: $text, prompt: Text(.storiesNoteFieldPrompt), axis: .vertical) {
            Text(.storiesNoteFieldPrompt)
        }
        .focused($isFocused)
        .lineLimit(1...3)
        .font(PaeoniaTypography.body)
        .padding(PaeoniaSpacing.space16)
        .background(
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                .fill(.paeoniaSurfaceSecondary)
        )
        .onChange(of: text) { _, newText in
            if newText.count > StoryNote.maxLength {
                text = String(newText.prefix(StoryNote.maxLength))
            }
        }
    }

    private var hint: some View {
        HStack {
            Text(.storiesNoteExplainer(partnerName))
            Spacer(minLength: PaeoniaSpacing.space8)
            Text(verbatim: "\(text.count)/\(StoryNote.maxLength)")
                .monospacedDigit()
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaTextSecondary)
    }

    private var buttons: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Button {
                Task { await save(text) }
            } label: {
                Text(.storiesNoteShare)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: viewModel.isSavingNote))
            .disabled(StoriesViewModel.cleanNote(text) == nil || StoriesViewModel.cleanNote(text) == current?.text)

            if current != nil {
                Button {
                    Task { await save("") }
                } label: {
                    Text(.storiesNoteRemove)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .disabled(viewModel.isSavingNote)
            }
        }
    }

    private func save(_ note: String) async {
        if await viewModel.setNote(note) {
            dismiss()
        }
    }
}
