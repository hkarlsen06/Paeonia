import SwiftUI

/// The newest bans and unbans, with who did them and why.
struct AdminAuditLogView: View {
    @State private var viewModel: AdminAuditLogViewModel
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @MainActor
    init(gateway: any AdminGateway) {
        _viewModel = State(initialValue: AdminAuditLogViewModel(gateway: gateway))
    }

    var body: some View {
        List {
            Section {
                ForEach(viewModel.entries) { entry in
                    AdminAuditRow(entry: entry)
                }
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .listStyle(.insetGrouped)
        .paeoniaGroupedList()
        .overlay {
            if !viewModel.hasLoaded {
                ProgressView()
            } else if viewModel.entries.isEmpty {
                PaeoniaEmptyStateView(
                    title: .adminAuditEmptyTitle,
                    message: .adminAuditEmptyMessage,
                    systemImage: "list.bullet.rectangle"
                )
            }
        }
        .navigationTitle(Text(.adminAuditTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else {
                return
            }
            bannerCenter.show(notice.banner)
            viewModel.dismissNotice()
        }
    }
}
