import SwiftUI

/// Sheet editor for the relationship start date. Owns its whole presentation
/// (navigation bar, detent, background), so callers only need
/// `.sheet { RelationshipDateEditorView(...) }`. Do not push it onto an
/// existing navigation stack — the nested `NavigationStack` would render a
/// second navigation bar inside the screen.
struct RelationshipDateEditorView: View {
    @Binding var selectedDate: Date
    let isEditing: Bool
    let isSaving: Bool
    let onSave: (Date) async -> Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            editorContent
                .navigationTitle(
                    Text(isEditing ? .homeMilestoneEditorEditTitle : .homeMilestoneEditorSetupTitle)
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { editorToolbar }
        }
        .presentationDetents([.large])
        .presentationBackground(.paeoniaSurfacePrimary)
        .interactiveDismissDisabled(isSaving)
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
            Text(isEditing ? .homeMilestoneEditorEditMessage : .homeMilestoneEditorSetupMessage)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            DatePicker(
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            ) {
                Text(.homeMilestoneEditorDateLabel)
            }
            .datePickerStyle(.graphical)
            .tint(.paeoniaAccentPrimary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space16)
        .background(.paeoniaSurfacePrimary)
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: { dismiss() }) {
                Text(.homeMilestoneEditorCancelAction)
            }
            .disabled(isSaving)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button(action: save) {
                if isSaving {
                    ProgressView()
                        .accessibilityHidden(true)
                } else {
                    Text(.homeMilestoneEditorSaveAction)
                }
            }
            .disabled(isSaving)
            // The spinner fades in over the save label instead of snapping while
            // the save settles in the background.
            .animation(PaeoniaMotion.stateChange, value: isSaving)
            .accessibilityLabel(
                Text(isSaving ? .homeMilestoneEditorSavingAction : .homeMilestoneEditorSaveAction)
            )
        }
    }

    private func save() {
        Task {
            if await onSave(selectedDate) {
                dismiss()
            }
        }
    }
}
