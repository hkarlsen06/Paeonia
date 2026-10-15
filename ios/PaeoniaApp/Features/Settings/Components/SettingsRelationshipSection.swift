import SwiftUI

/// The Us tab's relationship section: the couple's dates and location sharing. A date
/// that isn't set yet gets its own row here so it's easy to find. Set dates move to
/// the Important dates screen, since they rarely change.
struct SettingsRelationshipSection: View {
    let relationshipDateRow: RelationshipDateSettingsRow
    /// Hidden while there is no couple dates model. The partner's row is also hidden
    /// while there is no partner.
    let yourBirthdayRow: BirthdaySettingsRow?
    let partnerBirthdayRow: BirthdaySettingsRow?
    let locationViewModel: LocationMapViewModel
    let partnerName: String

    var body: some View {
        Section {
            if hasSetDate {
                datesLink
            }

            if !relationshipDateRow.isSet {
                relationshipDateRow
            }

            if let yourBirthdayRow, !yourBirthdayRow.isSet {
                yourBirthdayRow
            }

            if let partnerBirthdayRow, !partnerBirthdayRow.isSet {
                partnerBirthdayRow
            }

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

    private var datesLink: some View {
        NavigationLink {
            RelationshipDatesSettingsView(
                relationshipDateRow: relationshipDateRow,
                yourBirthdayRow: yourBirthdayRow,
                partnerBirthdayRow: partnerBirthdayRow
            )
        } label: {
            Label {
                Text(.settingsRelationshipDatesTitle)
            } icon: {
                Image(systemName: "calendar")
            }
        }
    }

    private var hasSetDate: Bool {
        relationshipDateRow.isSet || yourBirthdayRow?.isSet == true || partnerBirthdayRow?.isSet == true
    }
}
