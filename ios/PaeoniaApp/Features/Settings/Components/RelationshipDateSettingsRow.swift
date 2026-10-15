import SwiftUI

/// A Settings row for the day the couple got together. Shows the date once it is set.
struct RelationshipDateSettingsRow: View {
    let relationshipStartedOn: String?
    let isSaving: Bool
    let onSave: (Date) async -> Bool

    @State private var selectedDate = Date()
    @State private var isEditing = false

    var isSet: Bool { relationshipStartedOn != nil }

    var body: some View {
        // The date editor is a modal task (Cancel/Save), so it presents as a
        // sheet, same as from the Home tab milestone tile, instead of a push
        // that would nest the editor's own navigation stack.
        Button {
            selectedDate = relationshipStartDate ?? Date()
            isEditing = true
        } label: {
            LabeledContent {
                if let relationshipStartDate {
                    Text(relationshipStartDate, format: .dateTime.day().month().year())
                }
            } label: {
                // A Button row draws its label in the tint color, so match the
                // NavigationLink rows.
                Label {
                    Text(.settingsRelationshipDateTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                } icon: {
                    Image(systemName: "calendar")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            RelationshipDateEditorView(
                selectedDate: $selectedDate,
                isEditing: isSet,
                isSaving: isSaving,
                onSave: onSave
            )
        }
    }

    private var relationshipStartDate: Date? {
        relationshipStartedOn
            .flatMap { try? PairingStartDate(rawValue: $0) }
            .flatMap { $0.date() }
    }
}
