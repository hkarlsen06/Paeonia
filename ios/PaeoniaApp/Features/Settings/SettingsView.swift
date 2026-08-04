import SwiftUI

/// The "Me" tab: the couple member's personal corner, and a menu rather than a
/// control panel.
///
/// Every switch and destructive action lives one push away on its own screen, so
/// this stays short enough to scan and nothing important is reachable by accident
/// while scrolling past it.
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    let currentUserID: UUID?
    let currentDisplayName: String?
    let currentCustomProfilePhotoAssetID: UUID?
    let currentProviderProfilePhotoAssetID: UUID?
    let currentAuthProvider: AuthProvider?
    let partnerUserID: UUID?
    let relationshipStartedOn: String?
    let milestoneIsSaving: Bool
    let onSaveRelationshipStartedOn: (Date) async -> Bool
    let locationViewModel: LocationMapViewModel
    /// The partner's display name, so location/notification copy names the partner
    /// instead of saying "your partner".
    let partnerName: String
    /// Called after the couple is successfully unpaired, so the root can re-resolve
    /// access and move the user back to the unpaired flow.
    let onLeftRelationship: () -> Void
    /// Called to sign out on this device. The root ends the session and returns to
    /// the sign-in flow.
    let onLogout: () -> Void
    /// Routed through RootView so paired deletion shares the normal auth/session
    /// teardown and local privacy cleanup path.
    let onDeleteAccount: () -> Void
    let onUpdateProfile: @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool
    let onPurchasesRestored: @MainActor @Sendable () async -> Void
    private let privacySafetyService: (any PrivacySafetyServicing)?
    private let privacyOperationProvider: (any SyncClientOperationProviding)?
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @State private var selectedRelationshipDate = Date()
    @State private var isEditingRelationshipDate = false

    @MainActor
    init(
        viewModel: SettingsViewModel? = nil,
        currentUserID: UUID? = nil,
        currentDisplayName: String? = nil,
        currentCustomProfilePhotoAssetID: UUID? = nil,
        currentProviderProfilePhotoAssetID: UUID? = nil,
        currentAuthProvider: AuthProvider? = nil,
        partnerUserID: UUID? = nil,
        relationshipStartedOn: String? = nil,
        milestoneIsSaving: Bool = false,
        onSaveRelationshipStartedOn: @escaping (Date) async -> Bool = { _ in false },
        locationViewModel: LocationMapViewModel,
        partnerName: String,
        onLeftRelationship: @escaping () -> Void = {},
        onLogout: @escaping () -> Void = {},
        onDeleteAccount: @escaping () -> Void = {},
        onUpdateProfile: @escaping @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool =
            { _, _ in false },
        onPurchasesRestored: @escaping @MainActor @Sendable () async -> Void = {},
        privacySafetyService: (any PrivacySafetyServicing)? = PrivacySafetyServiceFactory.makeDefault(),
        privacyOperationProvider: (any SyncClientOperationProviding)? = nil
    ) {
        self.currentUserID = currentUserID
        self.currentDisplayName = currentDisplayName
        self.currentCustomProfilePhotoAssetID = currentCustomProfilePhotoAssetID
        self.currentProviderProfilePhotoAssetID = currentProviderProfilePhotoAssetID
        self.currentAuthProvider = currentAuthProvider
        self.partnerUserID = partnerUserID
        self.relationshipStartedOn = relationshipStartedOn
        self.milestoneIsSaving = milestoneIsSaving
        self.onSaveRelationshipStartedOn = onSaveRelationshipStartedOn
        self.locationViewModel = locationViewModel
        self.partnerName = partnerName
        self.onLeftRelationship = onLeftRelationship
        self.onLogout = onLogout
        self.onDeleteAccount = onDeleteAccount
        self.onUpdateProfile = onUpdateProfile
        self.onPurchasesRestored = onPurchasesRestored
        self.privacySafetyService = privacySafetyService
        self.privacyOperationProvider = privacyOperationProvider
        _viewModel = State(
            initialValue: viewModel ?? SettingsViewModel(userID: currentUserID?.uuidString)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                profileRow
                relationshipSection
                appSection
                SettingsDestinationLinksView()
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.mainTabYou))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.load()
        }
        // The notices come from screens pushed on top of this one, but this view
        // owns the view model and stays alive underneath them, so the banner keeps
        // working from here.
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else {
                return
            }
            showBanner(for: notice)
            viewModel.dismissNotice()
        }
        .sheet(isPresented: $isEditingRelationshipDate) {
            RelationshipDateEditorView(
                selectedDate: $selectedRelationshipDate,
                isEditing: relationshipStartedOn != nil,
                isSaving: milestoneIsSaving,
                onSave: onSaveRelationshipStartedOn
            )
        }
    }
}

// MARK: - Menu

extension SettingsView {
    /// The tab opens on the user's own identity. Name and photo are edited on the
    /// screen behind it, together with the account actions.
    private var profileRow: some View {
        PaeoniaCard(padding: 0) {
            NavigationLink {
                ProfileSettingsView(
                    viewModel: viewModel,
                    savedDisplayName: currentDisplayName,
                    customProfilePhotoAssetID: currentCustomProfilePhotoAssetID,
                    providerProfilePhotoAssetID: currentProviderProfilePhotoAssetID,
                    authProvider: currentAuthProvider,
                    partnerName: partnerName,
                    onSave: { [onUpdateProfile] displayName, photoUpdate in
                        await onUpdateProfile(displayName, photoUpdate)
                    },
                    onLeftRelationship: onLeftRelationship,
                    onLogout: onLogout,
                    onDeleteAccount: onDeleteAccount
                )
            } label: {
                SettingsProfileRow(
                    displayName: currentDisplayName,
                    customProfilePhotoAssetID: currentCustomProfilePhotoAssetID,
                    providerProfilePhotoAssetID: currentProviderProfilePhotoAssetID
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var relationshipSection: some View {
        SettingsMenuSection(title: .settingsRelationshipSectionTitle) {
            // The date editor is a modal task (Cancel/Save), so it presents as a
            // sheet — same as from the Us-tab milestone tile — instead of a push
            // that would nest the editor's own navigation stack.
            Button {
                selectedRelationshipDate = relationshipStartedOn
                    .flatMap { try? PairingStartDate(rawValue: $0) }
                    .flatMap { $0.date() }
                    ?? Date()
                isEditingRelationshipDate = true
            } label: {
                PaeoniaDisclosureRow(
                    title: .settingsRelationshipDateTitle,
                    message: relationshipStartedOn == nil
                        ? .settingsRelationshipDateMissingMessage
                        : .settingsRelationshipDateSetMessage,
                    systemImage: "calendar"
                )
            }
            .buttonStyle(.plain)

            SettingsMenuDivider()

            NavigationLink {
                LocationSettingsView(
                    viewModel: locationViewModel,
                    partnerName: partnerName
                )
            } label: {
                PaeoniaDisclosureRow(
                    title: .settingsLocationSectionTitle,
                    message: .settingsLocationRowMessage(partnerName),
                    systemImage: "location.fill"
                )
            }
            .buttonStyle(.plain)

            privacySafetyRows
        }
    }

    @ViewBuilder
    private var privacySafetyRows: some View {
        if let partnerUserID {
            SettingsMenuDivider()

            NavigationLink {
                PrivacySafetyView(
                    partnerUserID: partnerUserID,
                    partnerName: partnerName,
                    service: privacySafetyService,
                    operationProvider: privacyOperationProvider,
                    onReportedAndLeft: onLeftRelationship
                )
            } label: {
                PaeoniaDisclosureRow(
                    title: .privacySafetyTitle,
                    message: .settingsPrivacySafetyMessage,
                    systemImage: "checkmark.shield.fill"
                )
            }
            .buttonStyle(.plain)

            SettingsMenuDivider()

            // Reporting is a safety action, so keep it directly reachable from the
            // Me tab instead of requiring the user to discover it inside the
            // privacy-request screen. The destination still makes the
            // relationship-ending consequence explicit before anything is sent.
            NavigationLink {
                ReportAndLeaveView(
                    partnerUserID: partnerUserID,
                    partnerName: partnerName,
                    service: privacySafetyService,
                    operationProvider: privacyOperationProvider,
                    onReportedAndLeft: onLeftRelationship
                )
            } label: {
                PaeoniaDisclosureRow(
                    title: .privacySafetyReportTitle(partnerName),
                    message: .privacySafetyReportDescription(partnerName),
                    systemImage: "exclamationmark.shield",
                    iconTint: .paeoniaError
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var appSection: some View {
        SettingsMenuSection(title: .settingsSectionApp) {
            NavigationLink {
                NotificationSettingsView(
                    viewModel: viewModel,
                    partnerName: partnerName
                )
            } label: {
                PaeoniaDisclosureRow(
                    title: .settingsNotificationsSectionTitle,
                    message: .settingsNotificationsRowMessage,
                    systemImage: "bell.badge.fill"
                )
            }
            .buttonStyle(.plain)

            SettingsMenuDivider()

            NavigationLink {
                PurchaseSettingsView(
                    viewModel: viewModel,
                    onPurchasesRestored: { [onPurchasesRestored] in
                        await onPurchasesRestored()
                    }
                )
            } label: {
                PaeoniaDisclosureRow(
                    title: .settingsPurchasesSectionTitle,
                    message: .settingsPurchasesRowMessage,
                    systemImage: "creditcard"
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Notices

extension SettingsView {
    private func showBanner(for notice: SettingsViewModel.Notice) {
        switch notice {
        case .saveFailed:
            bannerCenter.show(
                .error(
                    title: String(localized: .settingsNotificationsSaveErrorTitle),
                    message: String(localized: .settingsNotificationsSaveErrorMessage)
                )
            )
        case .leaveFailed:
            bannerCenter.show(.error(message: String(localized: .pairingUnpairFailed)))
        case .purchasesRestored:
            bannerCenter.show(
                .info(
                    title: String(localized: .settingsPurchasesRestoredTitle),
                    message: String(localized: .settingsPurchasesRestoredMessage)
                )
            )
        case .noPurchasesToRestore:
            bannerCenter.show(
                .info(
                    title: String(localized: .settingsPurchasesNoneTitle),
                    message: String(localized: .settingsPurchasesNoneMessage)
                )
            )
        case .restorePurchasesFailed:
            bannerCenter.show(
                .error(
                    title: String(localized: .settingsPurchasesFailedTitle),
                    message: String(localized: .settingsPurchasesFailedMessage)
                )
            )
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(locationViewModel: LocationMapViewModel(), partnerName: "Oda")
    }
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
