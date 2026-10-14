import SwiftUI

/// One user's account facts, their partner, and the ban and unban actions.
struct AdminUserDetailView: View {
    private let gateway: any AdminGateway
    private let onChanged: @MainActor () async -> Void
    @State private var viewModel: AdminUserDetailViewModel
    @State private var isBanning = false
    @State private var isConfirmingUnban = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @MainActor
    init(
        userID: UUID,
        gateway: any AdminGateway,
        onChanged: @escaping @MainActor () async -> Void = {}
    ) {
        self.gateway = gateway
        self.onChanged = onChanged
        _viewModel = State(
            initialValue: AdminUserDetailViewModel(userID: userID, gateway: gateway, onChanged: onChanged)
        )
    }

    var body: some View {
        List {
            if let user = viewModel.user {
                header(user)
                Group {
                    accountSection(user)
                    relationshipSection(user)
                    reportsSection(user)
                    if user.isBanned {
                        banSection(user)
                    }
                    actionsSection(user)
                    historySection
                }
                .listRowBackground(Color.paeoniaSurfacePrimary)
            }
        }
        .listStyle(.insetGrouped)
        .paeoniaGroupedList()
        .overlay { overlay }
        .navigationTitle(Text(viewModel.user?.nameForMessages ?? ""))
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
        .sheet(isPresented: $isBanning) {
            AdminBanReasonSheet(
                userName: viewModel.user?.nameForMessages ?? "",
                isWorking: viewModel.isWorking,
                onBan: { reason in await viewModel.ban(reason: reason) }
            )
        }
        .alert(
            Text(.adminUnbanConfirmTitle(viewModel.user?.nameForMessages ?? "")),
            isPresented: $isConfirmingUnban
        ) {
            Button {
                Task { await viewModel.unban() }
            } label: {
                Text(.adminUnbanConfirmAction)
            }

            Button(role: .cancel, action: {}) {
                Text(.commonCancel)
            }
        } message: {
            Text(.adminUnbanConfirmMessage)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if !viewModel.hasLoaded {
            ProgressView()
        } else if viewModel.user == nil {
            PaeoniaEmptyStateView(
                title: .adminUsersEmptyTitle,
                message: .adminErrorUserNotFound,
                systemImage: "person.slash"
            )
        }
    }
}

// MARK: - Sections

extension AdminUserDetailView {
    private func labeled<Content: View>(
        _ title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LabeledContent {
            content()
        } label: {
            Text(title)
        }
    }
}

extension AdminUserDetailView {
    private func header(_ user: AdminUserDetail) -> some View {
        Section {
            VStack(spacing: PaeoniaSpacing.space8) {
                AdminUserName(name: user.displayName)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)

                AdminUserTags(isAdmin: user.isAdmin, isBanned: user.isBanned)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    private func accountSection(_ user: AdminUserDetail) -> some View {
        Section {
            labeled(.adminDetailProvider) {
                Text(user.authProvider.adminTitle)
            }
            labeled(.adminDetailSignedUp) {
                Text(user.createdAt, format: .dateTime.day().month().year())
            }
            labeled(.adminDetailFinishedSetup) {
                if let finished = user.onboardingCompletedAt {
                    Text(finished, format: .dateTime.day().month().year())
                } else {
                    Text(.adminDetailNotYet)
                }
            }
            labeled(.adminDetailTimeZone) {
                if let timeZoneID = user.timeZoneID {
                    Text(timeZoneID)
                } else {
                    Text(.adminDetailUnknown)
                }
            }
            labeled(.adminDetailFullAccess) {
                Text(user.isEntitled ? LocalizedStringResource.adminDetailYes : .adminDetailNo)
            }
            labeled(.adminDetailUserID) {
                Text(user.userID.uuidString.lowercased())
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        } header: {
            Text(.adminDetailAccountSection)
        }
    }

    @ViewBuilder
    private func relationshipSection(_ user: AdminUserDetail) -> some View {
        Section {
            if let partnerUserID = user.partnerUserID {
                NavigationLink {
                    AdminUserDetailView(userID: partnerUserID, gateway: gateway, onChanged: { await onChanged() })
                } label: {
                    labeled(.adminDetailPartner) {
                        AdminUserName(name: user.partnerDisplayName)
                    }
                }
                if let pairedSince = user.pairedSinceDate {
                    labeled(.adminDetailPairedSince) {
                        Text(pairedSince, format: .dateTime.day().month().year())
                    }
                }
            } else {
                Text(.adminDetailNotPaired)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        } header: {
            Text(.adminDetailRelationshipSection)
        }
    }

    private func reportsSection(_ user: AdminUserDetail) -> some View {
        Section {
            labeled(.adminDetailReportsAgainst) {
                Text(user.reportsAgainstCount, format: .number)
            }
            labeled(.adminDetailReportsBy) {
                Text(user.reportsByCount, format: .number)
            }
        } header: {
            Text(.adminDetailReportsSection)
        }
    }

    private func banSection(_ user: AdminUserDetail) -> some View {
        Section {
            if let bannedAt = user.bannedAt {
                labeled(.adminDetailBannedOn) {
                    Text(bannedAt, format: .dateTime.day().month().year().hour().minute())
                }
            }
            if let bannedBy = user.bannedByDisplayName?.trimmedNonEmpty {
                labeled(.adminDetailBannedBy) {
                    Text(bannedBy)
                }
            }
            if let reason = user.banReason {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    Text(.adminDetailBanReason)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                    Text(reason)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text(.adminDetailBanSection)
        }
    }

    /// Ban shows for others who are not admins. Unban shows for anyone banned.
    private func actionsSection(_ user: AdminUserDetail) -> some View {
        Section {
            if user.canUnban {
                SettingsActionRow(
                    title: .adminDetailUnbanAction,
                    systemImage: "person.crop.circle.badge.checkmark",
                    isBusy: viewModel.isWorking
                ) {
                    isConfirmingUnban = true
                }
            } else if user.canBan {
                SettingsActionRow(
                    title: .adminDetailBanAction,
                    systemImage: "nosign",
                    role: .destructive,
                    isBusy: viewModel.isWorking
                ) {
                    isBanning = true
                }
            }
        } footer: {
            if !user.canBan, !user.canUnban {
                Text(.adminDetailCannotBan)
            }
        }
    }

    private var historySection: some View {
        Section {
            if viewModel.history.isEmpty {
                Text(.adminDetailHistoryEmpty)
                    .foregroundStyle(.paeoniaTextSecondary)
            } else {
                ForEach(viewModel.history) { entry in
                    AdminAuditRow(entry: entry)
                }
            }
        } header: {
            Text(.adminDetailHistorySection)
        }
    }
}
