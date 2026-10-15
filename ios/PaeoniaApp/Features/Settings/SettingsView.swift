import SwiftUI

/// The Us tab: the couple at the top, then a menu rather than a control panel.
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
    let partnerProfilePhotoAssetID: UUID?
    let relationshipStartedOn: String?
    let milestoneIsSaving: Bool
    let onSaveRelationshipStartedOn: (Date) async -> Bool
    /// Both partners' birthdays, side by side in the relationship section. Nil hides
    /// both rows.
    let coupleDates: CoupleDatesViewModel?
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
    /// Builds the sheet for this person's mark in the board games. Without it
    /// the row is hidden.
    let loadMarkEditor: (@MainActor () async -> BoardMarkEditorModel?)?
    private let privacySafetyService: (any PrivacySafetyServicing)?
    private let privacyOperationProvider: (any SyncClientOperationProviding)?
    private let adminGateway: (any AdminGateway)?
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var profileAvatarSize: CGFloat = 56

    /// Lives here rather than on the profile screen, so a save keeps its state
    /// and still reports back after the user leaves that screen.
    @State private var profileEditor = ProfileEditorViewModel()
    /// Decides whether the Admin row shows. The server checks again on every admin call.
    @State private var adminAccess: AdminAccessModel

    @MainActor
    init(
        viewModel: SettingsViewModel? = nil,
        currentUserID: UUID? = nil,
        currentDisplayName: String? = nil,
        currentCustomProfilePhotoAssetID: UUID? = nil,
        currentProviderProfilePhotoAssetID: UUID? = nil,
        currentAuthProvider: AuthProvider? = nil,
        partnerUserID: UUID? = nil,
        partnerProfilePhotoAssetID: UUID? = nil,
        relationshipStartedOn: String? = nil,
        milestoneIsSaving: Bool = false,
        onSaveRelationshipStartedOn: @escaping (Date) async -> Bool = { _ in false },
        coupleDates: CoupleDatesViewModel? = nil,
        locationViewModel: LocationMapViewModel,
        partnerName: String,
        onLeftRelationship: @escaping () -> Void = {},
        onLogout: @escaping () -> Void = {},
        onDeleteAccount: @escaping () -> Void = {},
        isLoggingOut: Bool = false,
        onUpdateProfile: @escaping @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool =
            { _, _ in false },
        onPurchasesRestored: @escaping @MainActor @Sendable () async -> Void = {},
        loadMarkEditor: (@MainActor () async -> BoardMarkEditorModel?)? = nil,
        privacySafetyService: (any PrivacySafetyServicing)? = PrivacySafetyServiceFactory.makeDefault(),
        privacyOperationProvider: (any SyncClientOperationProviding)? = nil,
        adminGateway: (any AdminGateway)? = AdminGatewayFactory.makeDefault()
    ) {
        self.currentUserID = currentUserID
        self.currentDisplayName = currentDisplayName
        self.currentCustomProfilePhotoAssetID = currentCustomProfilePhotoAssetID
        self.currentProviderProfilePhotoAssetID = currentProviderProfilePhotoAssetID
        self.currentAuthProvider = currentAuthProvider
        self.partnerUserID = partnerUserID
        self.partnerProfilePhotoAssetID = partnerProfilePhotoAssetID
        self.relationshipStartedOn = relationshipStartedOn
        self.milestoneIsSaving = milestoneIsSaving
        self.onSaveRelationshipStartedOn = onSaveRelationshipStartedOn
        self.coupleDates = coupleDates
        self.locationViewModel = locationViewModel
        self.partnerName = partnerName
        self.onLeftRelationship = onLeftRelationship
        self.onLogout = onLogout
        self.onDeleteAccount = onDeleteAccount
        self.isLoggingOut = isLoggingOut
        self.onUpdateProfile = onUpdateProfile
        self.onPurchasesRestored = onPurchasesRestored
        self.loadMarkEditor = loadMarkEditor
        self.privacySafetyService = privacySafetyService
        self.privacyOperationProvider = privacyOperationProvider
        self.adminGateway = adminGateway
        _adminAccess = State(initialValue: AdminAccessModel(gateway: adminGateway))
        _viewModel = State(
            initialValue: viewModel ?? SettingsViewModel(userID: currentUserID?.uuidString)
        )
    }

    var body: some View {
        List {
            Section {
                coupleHeader
            }
            Group {
                Section {
                    profileRow
                }
                SettingsRelationshipSection(
                    relationshipDateRow: RelationshipDateSettingsRow(
                        relationshipStartedOn: relationshipStartedOn,
                        isSaving: milestoneIsSaving,
                        onSave: onSaveRelationshipStartedOn
                    ),
                    yourBirthdayRow: birthdayRow(for: currentUserID),
                    partnerBirthdayRow: birthdayRow(for: partnerUserID),
                    locationViewModel: locationViewModel,
                    partnerName: partnerName
                )
                appSection
                AdminSettingsSection(access: adminAccess, gateway: adminGateway)
                helpSection
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .listStyle(.insetGrouped)
        .paeoniaGroupedList(showsTabBackdrop: true)
        .navigationTitle(Text(.mainTabUs))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await adminAccess.refresh()
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
        .onChange(of: profileEditor.event) { _, event in
            guard let event else {
                return
            }
            showBanner(for: event)
            profileEditor.consumeEvent()
        }
        .sensoryFeedback(.success, trigger: profileEditor.completedSaveCount)
    }
}

// MARK: - Menu

extension SettingsView {
    /// Sits on the plum background instead of in a card, so it reads as the top of
    /// the page rather than a row.
    private var coupleHeader: some View {
        SettingsCoupleHeader(
            currentName: currentDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationYouName),
            currentProfilePhotoAssetID: currentCustomProfilePhotoAssetID ?? currentProviderProfilePhotoAssetID,
            partnerName: partnerName,
            partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
            relationshipStartedOn: relationshipStartedOn
        )
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    /// Name and photo are edited on the screen behind this row, above the account
    /// actions. Those are serious enough to sit one deliberate step away instead
    /// of on the menu.
    private var profileRow: some View {
        NavigationLink {
            ProfileSettingsView(
                editor: profileEditor,
                savedDisplayName: currentDisplayName,
                customProfilePhotoAssetID: currentCustomProfilePhotoAssetID,
                providerProfilePhotoAssetID: currentProviderProfilePhotoAssetID,
                onSave: { [onUpdateProfile] displayName, photoUpdate in
                    await onUpdateProfile(displayName, photoUpdate)
                },
                accountSection: SettingsAccountSection(
                    viewModel: viewModel,
                    authProvider: currentAuthProvider,
                    partnerName: partnerName,
                    onLeftRelationship: onLeftRelationship,
                    onLogout: onLogout,
                    onDeleteAccount: onDeleteAccount,
                    isLoggingOut: isLoggingOut
                )
            )
        } label: {
            HStack(spacing: PaeoniaSpacing.space16) {
                PaeoniaProfilePhotoAvatar(
                    mediaAssetID: currentCustomProfilePhotoAssetID ?? currentProviderProfilePhotoAssetID,
                    name: profileRowName,
                    tint: .paeoniaPartnerOne,
                    size: min(profileAvatarSize, 72)
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    Text(profileRowName)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Clerk keeps the email with its saved session, so this works offline.
                    if let email = PaeoniaClerk.currentEmail() {
                        Text(email)
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextSecondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .truncationMode(.middle)
                    }
                }
                .layoutPriority(1)
            }
            .padding(.vertical, PaeoniaSpacing.space4)
        }
    }

    private var profileRowName: String {
        currentDisplayName?.trimmedNonEmpty ?? String(localized: .settingsProfileFallbackName)
    }

    private func birthdayRow(for userID: UUID?) -> BirthdaySettingsRow? {
        guard let userID, let coupleDates else { return nil }
        return BirthdaySettingsRow(
            userID: userID,
            coupleDates: coupleDates,
            names: CoupleDateNames(currentUserID: currentUserID, partnerUserID: partnerUserID, partnerName: partnerName)
        )
    }

    private var appSection: some View {
        Section {
            NavigationLink {
                NotificationSettingsView(
                    viewModel: viewModel,
                    partnerName: partnerName
                )
            } label: {
                Label {
                    Text(.settingsNotificationsSectionTitle)
                } icon: {
                    Image(systemName: "bell.badge.fill")
                }
            }

            if let loadMarkEditor {
                SettingsMarkRow(loadEditor: { await loadMarkEditor() })
            }

            NavigationLink {
                PurchaseSettingsView(
                    viewModel: viewModel,
                    onPurchasesRestored: { [onPurchasesRestored] in
                        await onPurchasesRestored()
                    }
                )
            } label: {
                Label {
                    Text(.settingsPurchasesSectionTitle)
                } icon: {
                    Image(systemName: "creditcard")
                }
            }
        } header: {
            Text(.settingsSectionApp)
        }
    }

    /// Privacy requests and reporting share one screen. Reporting ends the
    /// relationship, so it waits there behind a deliberate tap instead of sitting
    /// on the menu.
    private var helpSection: some View {
        Section {
            NavigationLink {
                PrivacySafetyView(
                    partnerUserID: partnerUserID,
                    partnerName: partnerName,
                    service: privacySafetyService,
                    operationProvider: privacyOperationProvider,
                    onReportedAndLeft: onLeftRelationship
                )
            } label: {
                Label {
                    Text(.privacySafetyTitle)
                } icon: {
                    Image(systemName: "checkmark.shield.fill")
                }
            }

            supportRow
        } footer: {
            PaeoniaLegalLinksView()
                .frame(maxWidth: .infinity)
                .padding(.top, PaeoniaSpacing.space16)
        }
    }

    @ViewBuilder
    private var supportRow: some View {
        if let supportURL = URL(string: "https://paeonia.no/support") {
            Link(destination: supportURL) {
                LabeledContent {
                    Image(systemName: "arrow.up.right")
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .accessibilityHidden(true)
                } label: {
                    Label {
                        Text(.authSignInSupport)
                            .foregroundStyle(.paeoniaTextPrimary)
                    } icon: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
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
        case let .restorePurchasesFailed(failure):
            bannerCenter.show(
                .error(
                    title: String(localized: .settingsPurchasesFailedTitle),
                    message: String(localized: failure.restorePurchasesMessage)
                )
            )
        case .purchaseLinkedToAnotherAccount:
            bannerCenter.show(
                .error(
                    title: String(localized: .settingsPurchasesLinkedElsewhereTitle),
                    message: String(localized: .settingsPurchasesLinkedElsewhereMessage),
                    timing: .untilDismissed
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

private extension PaeoniaFailure {
    /// Only a phone without a connection is told to check it.
    var restorePurchasesMessage: LocalizedStringResource {
        self == .offline ? .settingsPurchasesFailedMessage : .commonActionFailedMessage
    }
}
