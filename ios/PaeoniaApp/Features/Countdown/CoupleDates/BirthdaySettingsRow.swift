import SwiftUI

/// A Settings row for one partner's birthday: the date, or "Add" while none is set.
/// Opens the same editor as the milestones timeline, so the birthday can be found
/// without a relationship start date.
struct BirthdaySettingsRow: View {
    let userID: UUID
    let coupleDates: CoupleDatesViewModel
    let names: CoupleDateNames

    @State private var isEditing = false

    var isSet: Bool { birthday != nil }

    var body: some View {
        // A modal task (Cancel/Save), so it presents as a sheet like the relationship date.
        Button { isEditing = true } label: {
            LabeledContent {
                if let birthday {
                    Text(birthday, format: .dateTime.day().month().year())
                } else {
                    Text(.settingsBirthdayAdd)
                }
            } label: {
                // A Button row draws its label in the tint color, so match the
                // NavigationLink rows.
                Label {
                    Text(verbatim: CoupleDateNames.birthdayTitle(for: userID, names: names))
                        .foregroundStyle(.paeoniaTextPrimary)
                } icon: {
                    Image(systemName: "gift")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            CoupleDateEditorSheet(editor: .birthday(userID), coupleDates: coupleDates, names: names)
                .analyticsScreen("couple_date_editor")
        }
    }

    private var birthday: Date? {
        coupleDates.dates.birthdays[userID]
            .flatMap { try? PairingStartDate(rawValue: $0) }?
            .date()
    }
}
