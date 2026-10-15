import SwiftUI

/// The Us tab's relationship section: the day you got together, the partner's
/// birthday, and location sharing.
struct SettingsRelationshipSection: View {
    let relationshipStartedOn: String?
    let isSavingStartedOn: Bool
    let onSaveStartedOn: (Date) async -> Bool
    /// Hidden while there is no partner or no couple dates model.
    let partnerBirthdayRow: BirthdaySettingsRow?
    let locationViewModel: LocationMapViewModel
    let partnerName: String

    @State private var selectedDate = Date()
    @State private var isEditingDate = false

    var body: some View {
        Section {
            relationshipDateRow

            partnerBirthdayRow

            NavigationLink {
                LocationSettingsView(
                    viewModel: locationViewModel,
                    partnerName: partnerName
                )
            } label: {
                Label {
                    Text(.settingsLocationSectionTitle)
                } icon: {
                    Image(systemName: "location.fill")
                }
            }
        } header: {
            Text(.settingsRelationshipSectionTitle)
        }
    }

    private var relationshipDateRow: some View {
        // The date editor is a modal task (Cancel/Save), so it presents as a
        // sheet, same as from the Home tab milestone tile, instead of a push
        // that would nest the editor's own navigation stack.
        Button {
            selectedDate = relationshipStartDate ?? Date()
            isEditingDate = true
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
        .sheet(isPresented: $isEditingDate) {
            RelationshipDateEditorView(
                selectedDate: $selectedDate,
                isEditing: relationshipStartedOn != nil,
                isSaving: isSavingStartedOn,
                onSave: onSaveStartedOn
            )
        }
    }

    private var relationshipStartDate: Date? {
        relationshipStartedOn
            .flatMap { try? PairingStartDate(rawValue: $0) }
            .flatMap { $0.date() }
    }
}
