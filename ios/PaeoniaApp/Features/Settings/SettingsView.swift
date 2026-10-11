import SwiftUI

/// The "Me" tab: the couple member's personal corner, and a menu rather than a
/// control panel.
///
/// Every switch lives one push away on its own screen, so this stays short enough
/// to scan. The account actions sit last, and each one only opens a centered
/// confirmation, so nothing important happens on a stray tap.
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
    /// True while the root signs out, so the log-out row shows progress.
    let isLoggingOut: Bool
    let onUpdateProfile: @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool
    let onPurchasesRestored: @MainActor @Sendable () async -> Void
    private let privacySafetyService: (any PrivacySafetyServicing)?
    private let privacyOperationProvider: (any SyncClientOperationProviding)?
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @State private var selectedRelationshipDate = Date()
    @State private var isEditingRelationshipDate = false
    /// Lives here rather than on the profile screen, so a save keeps its state
    /// and still reports back after the user leaves that screen.
    @State private var profileEditor = ProfileEditorViewModel()

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
        isLoggingOut: Bool = false,
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
        self.isLoggingOut = isLoggingOut
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
                privacySafetySection
                SettingsDestinationLinksView()
                SettingsAccountSection(
                    viewModel: viewModel,
                    authProvider: currentAuthProvider,
                    partnerName: partnerName,
                    onLeftRelationship: onLeftRelationship,
                    onLogout: onLogout,
                    onDeleteAccount: onDeleteAccount,
                    isLoggingOut: isLoggingOut
                )
                PaeoniaLegalLinksView()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space40)
            .paeoniaReadableWidth(alignment: .leading)
        }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.mainTabYou))
        .navigationBarTitleDisplayMode(.large)
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
        .onChange(of: profileEditor.event) { _, event in
            guard let event else {
                return
            }
            showBanner(for: event)
            profileEditor.consumeEvent()
        }
        .sensoryFeedback(.success, trigger: profileEditor.completedSaveCount)
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
                    editor: profileEditor,
                    savedDisplayName: currentDisplayName,
                    customProfilePhotoAssetID: currentCustomProfilePhotoAssetID,
                    providerProfilePhotoAssetID: currentProviderProfilePhotoAssetID,
                    onSave: { [onUpdateProfile] displayName, photoUpdate in
                        await onUpdateProfile(displayName, photoUpdate)
                    }
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
        }
    }

    /// Data requests and reporting get their own group so a safety action is
    /// easy to find without hunting through relationship settings.
    private var privacySafetySection: some View {
        SettingsMenuSection(title: .privacySafetyTitle) {
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
                    title: .privacySafetyRequestsSectionTitle,
                    message: .settingsPrivacySafetyMessage,
                    systemImage: "checkmark.shield.fill"
                )
            }
            .buttonStyle(.plain)

            reportRow
        }
    }

    @ViewBuilder
    private var reportRow: some View {
        if let partnerUserID {
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
    private func showBanner(for event: ProfileEditorViewModel.Event) {
        switch event {
        case .saved:
            bannerCenter.show(
                .info(
                    title: String(localized: .settingsProfileSavedTitle),
                    message: String(localized: .settingsProfileSavedMessage(partnerName))
                )
            )
        case .saveFailed:
            bannerCenter.show(
                .error(
                    title: String(localized: .settingsProfileSaveFailedTitle),
                    message: String(localized: .settingsProfileSaveFailedMessage)
                )
            )
        case .photoLoadFailed:
            bannerCenter.show(
                .error(
                    title: String(localized: .settingsProfilePhotoLoadFailedTitle),
                    message: String(localized: .settingsProfilePhotoLoadFailedMessage)
                )
            )
        }
    }

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
        case .purchaseLinkedToAnotherAccount:
            bannerCenter.show(
                .error(
                    title: String(localized: .settingsPurchasesLinkedElsewhereTitle),
                    message: String(localized: .settingsPurchasesLinkedElsewhereMessage)
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
