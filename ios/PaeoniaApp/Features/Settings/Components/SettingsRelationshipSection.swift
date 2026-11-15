import SwiftUI

/// The More tab's relationship section: the partner's nickname, the couple's dates,
/// location sharing and "Show when I'm here". A date that isn't set yet gets its own row here so it's easy to
/// find. Set dates move to the Important dates screen, since they rarely change.
struct SettingsRelationshipSection: View {
    /// Hidden while there is no partner.
    let nicknameRow: PartnerNicknameSettingsRow?
    let relationshipDateRow: RelationshipDateSettingsRow
    /// Hidden while there is no couple dates model. The partner's row is also hidden
    /// while there is no partner.
    let yourBirthdayRow: BirthdaySettingsRow?
    let partnerBirthdayRow: BirthdaySettingsRow?
    let locationViewModel: LocationMapViewModel
    let partnerName: String

    var body: some View {
        Section {
            if let nicknameRow {
                nicknameRow
            }

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
                .analyticsScreen("settings_location")
            } label: {
                SettingsMenuLabel(.settingsLocationSectionTitle, systemImage: "location.fill", value: locationValue)
            }

            PresenceSettingsRow(partnerName: partnerName)
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
            .analyticsScreen("settings_dates")
        } label: {
            SettingsMenuLabel(.settingsRelationshipDatesTitle, systemImage: "calendar")
        }
    }

    /// Reads the same state as the location screen. Nothing shows until the saved
    /// choice has loaded, so the row never shows a guess.
    private var locationValue: Text? {
        guard locationViewModel.isSharingLoaded else {
            return nil
        }
        if !locationViewModel.sharingEnabled || locationViewModel.authorizationState == .denied {
            return Text(.settingsValueOff)
        }
        return Text(locationViewModel.isSharingPaused ? .settingsValuePaused : .settingsValueOn)
    }

    private var hasSetDate: Bool {
        relationshipDateRow.isSet || yourBirthdayRow?.isSet == true || partnerBirthdayRow?.isSet == true
    }
}
