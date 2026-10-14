import SwiftUI

/// The row in the game settings sheet that opens the mark on this person's
/// pieces. The mark saves from its own sheet, apart from the settings' Save.
struct GameMarkSettingsRow: View {
    let viewModel: GamesViewModel

    @State private var editor: BoardMarkEditorModel?
    @State private var isLoading = false

    var body: some View {
        Button {
            Task {
                isLoading = true
                editor = await viewModel.makeMarkEditor()
                isLoading = false
            }
        } label: {
            label
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityIdentifier("games.settings.mark")
        .sheet(isPresented: isEditing) {
            if let editor {
                BoardMarkEditorView(color: .boardGameMine, model: editor)
            }
        }
    }

    private var label: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: "scribble.variable")
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(.boardGamesMarkTitle)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(.gamesSettingsMarkDetail)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                ProgressView()
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "chevron.right")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(minHeight: PaeoniaSpacing.buttonHeight)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                .strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeHairline)
        }
        .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
    }

    private var isEditing: Binding<Bool> {
        Binding(
            get: { editor != nil },
            set: { isPresented in
                if !isPresented {
                    editor = nil
                }
            }
        )
    }
}
