import SwiftUI

/// The round buttons at the top of the full-screen photo and video viewers.
private let viewerControlBackground = Color.black.opacity(0.75)

struct PaeoniaViewerCloseButton: View {
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(width: 44, height: 44)
                .background(Circle().fill(viewerControlBackground))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.commonClose))
        .accessibilityIdentifier(accessibilityIdentifier)
        .keyboardShortcut(.cancelAction)
    }
}

/// Spins while saving and turns into a check once the item is in Photos, like Tidex's gallery.
struct PaeoniaViewerSaveButton: View {
    let isSaving: Bool
    let isSaved: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: isSaved)
                }
            }
            .frame(width: 44, height: 44)
            .background(Circle().fill(viewerControlBackground))
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isSaved)
        .accessibilityLabel(Text(isSaved ? .imageViewerSaved : .imageViewerSave))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
