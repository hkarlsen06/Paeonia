import SwiftUI

/// The Admin row for the Us tab. It shows only after the server says this account
/// is an admin, and stays hidden while that check runs and when it fails.
struct AdminSettingsSection: View {
    let access: AdminAccessModel
    let gateway: (any AdminGateway)?

    var body: some View {
        if access.isAdmin, let gateway {
            Section {
                NavigationLink {
                    AdminHubView(gateway: gateway)
                } label: {
                    Label {
                        Text(.adminEntryTitle)
                    } icon: {
                        Image(systemName: "shield.lefthalf.filled")
                    }
                }
            }
        }
    }
}
