import SwiftUI

/// The round glass close button in the corner of the note screen.
struct StoryNoteCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.commonClose))
    }
}

/// The pill that shares a note, on the keyboard. It dims while there is nothing new to
/// share and shows a spinner while the note is sent.
struct StoryNoteShareButton: View {
    let isEnabled: Bool
    let isSaving: Bool
    let action: () -> Void

    private var looksEnabled: Bool { isEnabled || isSaving }

    var body: some View {
        Button(action: action) {
            Group {
                if isSaving {
                    ProgressView().tint(.paeoniaTextInverse)
                } else {
                    Text(.storiesNoteShare)
                }
            }
            .font(PaeoniaTypography.button)
            .foregroundStyle(looksEnabled ? .paeoniaTextInverse : .paeoniaTextTertiary)
            .padding(.horizontal, PaeoniaSpacing.space24)
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .background(Capsule().fill(looksEnabled ? .paeoniaAccentPrimary : .paeoniaSurfacePressed))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isSaving)
    }
}

/// Removes your note, under your avatar on the note screen.
struct StoryNoteRemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(.storiesNoteRemove)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
                .padding(PaeoniaSpacing.space12)
        }
        .buttonStyle(.plain)
    }
}
