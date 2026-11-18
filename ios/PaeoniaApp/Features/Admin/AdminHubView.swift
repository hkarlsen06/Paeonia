import SwiftUI

/// The admin area, pushed from the More tab. Nothing else links here, and the server
/// checks admin access again on every call.
struct AdminHubView: View {
    let gateway: any AdminGateway

    var body: some View {
        List {
            Group {
                casesSection
                peopleSection
                logSection
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .listStyle(.insetGrouped)
        .paeoniaGroupedList()
        .navigationTitle(Text(.adminHubTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var casesSection: some View {
        Section {
            NavigationLink {
                AdminOpenCasesView(gateway: gateway)
            } label: {
                Label {
                    Text(.adminHubOpenCases)
                } icon: {
                    Image(systemName: "exclamationmark.bubble.fill")
                }
            }
        } header: {
            Text(.adminHubCasesSection)
        }
    }

    private var peopleSection: some View {
        Section {
            NavigationLink {
                AdminUsersView(bannedOnly: false, gateway: gateway)
            } label: {
                Label {
                    Text(.adminHubUsers)
                } icon: {
                    Image(systemName: "person.2.fill")
                }
            }

            NavigationLink {
                AdminUsersView(bannedOnly: true, gateway: gateway)
            } label: {
                Label {
                    Text(.adminHubBannedUsers)
                } icon: {
                    Image(systemName: "nosign")
                }
            }
        } header: {
            Text(.adminHubPeopleSection)
        }
    }

    private var logSection: some View {
        Section {
            NavigationLink {
                AdminAuditLogView(gateway: gateway)
            } label: {
                Label {
                    Text(.adminHubAuditLog)
                } icon: {
                    Image(systemName: "list.bullet.rectangle")
                }
            }
        } header: {
            Text(.adminHubLogSection)
        }
    }
}
