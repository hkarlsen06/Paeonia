import SwiftUI

/// The couple's dates that are set: the day they got together and both partners'
/// birthdays. They rarely change, so they sit one step in from the Us tab. Dates
/// not set yet stay on the Us tab instead.
struct RelationshipDatesSettingsView: View {
    let relationshipDateRow: RelationshipDateSettingsRow
    let yourBirthdayRow: BirthdaySettingsRow?
    let partnerBirthdayRow: BirthdaySettingsRow?

    var body: some View {
        Form {
            Section {
                if relationshipDateRow.isSet {
                    relationshipDateRow
                }

                if let yourBirthdayRow, yourBirthdayRow.isSet {
                    yourBirthdayRow
                }

                if let partnerBirthdayRow, partnerBirthdayRow.isSet {
                    partnerBirthdayRow
                }
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .paeoniaGroupedList()
        .navigationTitle(Text(.settingsRelationshipDatesTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}
