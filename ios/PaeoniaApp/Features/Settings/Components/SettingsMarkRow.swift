import SwiftUI

/// Opens the sheet for the mark on this person's pieces in every board game.
/// Games asks for it once after setup, and this row is where it changes later.
struct SettingsMarkRow: View {
    let loadEditor: @MainActor () async -> BoardMarkEditorModel?

    @State private var editor: BoardMarkEditorModel?
    @State private var isLoading = false

    var body: some View {
        SettingsActionRow(
            title: .settingsGameMarkTitle,
            systemImage: "scribble.variable",
            isBusy: isLoading
        ) {
            Task {
                isLoading = true
                editor = await loadEditor()
                isLoading = false
            }
        }
        .accessibilityIdentifier("settings.gameMark")
        .sheet(isPresented: isEditing) {
            if let editor {
                BoardMarkEditorView(color: .boardGameMine, model: editor)
            }
        }
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
