import SwiftUI

/// Every user with search, or only the banned users.
struct AdminUsersView: View {
    private let gateway: any AdminGateway
    @State private var viewModel: AdminUsersViewModel
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @MainActor
    init(bannedOnly: Bool, gateway: any AdminGateway) {
        self.gateway = gateway
        _viewModel = State(initialValue: AdminUsersViewModel(bannedOnly: bannedOnly, gateway: gateway))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        // Banned users are listed without a search, so only the full list gets the field.
        if viewModel.bannedOnly {
            content
        } else {
            content.searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(.adminUsersSearchPrompt)
            )
        }
    }

    private var content: some View {
        List {
            Section {
                ForEach(viewModel.users) { user in
                    NavigationLink {
                        AdminUserDetailView(
                            userID: user.userID,
                            gateway: gateway,
                            onChanged: { [viewModel] in await viewModel.refresh() }
                        )
                    } label: {
                        AdminUserRow(user: user)
                    }
                }
            } footer: {
                if viewModel.isSearchTooShort {
                    Text(.adminUsersSearchTooShort)
                }
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .listStyle(.insetGrouped)
        .paeoniaGroupedList()
        .overlay { overlay }
        .navigationTitle(viewModel.bannedOnly ? Text(.adminUsersBannedTitle) : Text(.adminUsersTitle))
        .navigationBarTitleDisplayMode(.inline)
        // Runs again for each change of the text. Starting a new run cancels the
        // one before, which is what makes the debounce work.
        .task(id: viewModel.searchText) {
            await viewModel.search()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else {
                return
            }
            bannerCenter.show(notice.banner)
            viewModel.dismissNotice()
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if !viewModel.hasLoaded {
            ProgressView()
        } else if viewModel.users.isEmpty {
            if viewModel.bannedOnly {
                PaeoniaEmptyStateView(
                    title: .adminUsersBannedEmptyTitle,
                    message: .adminUsersBannedEmptyMessage,
                    systemImage: "nosign"
                )
            } else {
                PaeoniaEmptyStateView(
                    title: .adminUsersEmptyTitle,
                    message: .adminUsersEmptyMessage,
                    systemImage: "person.2.slash"
                )
            }
        }
    }
}
