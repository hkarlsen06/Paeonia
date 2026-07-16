import SwiftUI
import UIKit

/// The "Me" tab: the couple member's personal corner. Hosts location sharing,
/// notification settings (collapsed by default to stay compact), and the account
/// actions — log out, leave the relationship, and delete the account.
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    let currentUserID: UUID?
    let currentDisplayName: String?
    let currentProfilePhotoAssetID: UUID?
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
    @Environment(\.openURL) private var openURL

    /// Gates the leave action behind a centered confirmation alert, so the pairing
    /// can never end on a single stray tap.
    @State private var isConfirmingLeave = false
    @State private var isConfirmingDelete = false
    /// The notifications block is collapsed by default so the tab stays short; the
    /// user opens it when they want to change an alert.
    @State private var isNotificationsExpanded = false
    @State private var selectedRelationshipDate = Date()
    @State private var isEditingRelationshipDate = false

    @MainActor
    init(
        viewModel: SettingsViewModel? = nil,
        currentUserID: UUID? = nil,
        currentDisplayName: String? = nil,
        currentProfilePhotoAssetID: UUID? = nil,
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
        self.currentProfilePhotoAssetID = currentProfilePhotoAssetID
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
                profileSection
                relationshipSection
                locationSection
                notificationsSection
                restorePurchasesSection

                // Quiet destination cards read as one cluster, so the headerless
                // privacy card doesn't float alone between headed sections.
                VStack(spacing: PaeoniaSpacing.space12) {
                    privacySafetySection
                    SettingsDestinationLinksView()
                }

                accountActionsSection
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
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else {
                return
            }
            showBanner(for: notice)
            viewModel.dismissNotice()
        }
        .alert(
            Text(.pairingUnpairConfirmTitle(partnerName)),
            isPresented: $isConfirmingLeave
        ) {
            Button(role: .destructive, action: leaveRelationship) {
                Text(.pairingUnpairConfirmAction)
            }

            Button(role: .cancel, action: {}) {
                Text(.pairingUnpairConfirmCancel)
            }
        } message: {
            Text(.pairingUnpairConfirmMessage(partnerName))
        }
        .alert(
            Text(.authDeleteAccountConfirmTitle),
            isPresented: $isConfirmingDelete
        ) {
            Button(role: .destructive, action: onDeleteAccount) {
                Text(.authDeleteAccountConfirmAction)
            }

            Button(role: .cancel, action: {}) {
                Text(.authDeleteAccountConfirmCancel)
            }
        } message: {
            Text(.authDeleteAccountConfirmMessage)
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

extension SettingsView {
    // MARK: - Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            sectionHeader(.settingsProfileSectionTitle)

            PaeoniaCard(padding: 0) {
                NavigationLink {
                    PairedProfileEditorView(
                        displayName: profileDisplayName,
                        customProfilePhotoAssetID: currentCustomProfilePhotoAssetID,
                        providerProfilePhotoAssetID: currentProviderProfilePhotoAssetID,
                        authProvider: currentAuthProvider,
                        onSave: onUpdateProfile
                    )
                } label: {
                    profileRowLabel
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var profileRowLabel: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: currentProfilePhotoAssetID,
                name: profileDisplayName,
                tint: .paeoniaPartnerOne,
                size: 52
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(profileDisplayName)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(.settingsProfileEditAction)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        }
        .padding(PaeoniaSpacing.space16)
        .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
        .contentShape(Rectangle())
    }

    private var profileDisplayName: String {
        currentDisplayName?.trimmedNonEmpty
            ?? String(localized: .settingsProfileFallbackName)
    }

    // MARK: - Relationship

    private var relationshipSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            sectionHeader(.settingsRelationshipSectionTitle)

            PaeoniaCard(padding: 0) {
                // The date editor is a modal task (Cancel/Save), so it presents as
                // a sheet — same as from the Us-tab milestone tile — instead of a
                // push that would nest the editor's own navigation stack.
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
            }
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            sectionHeader(.settingsLocationSectionTitle)

            PaeoniaCard {
                settingRow(
                    title: .settingsLocationSharingTitle,
                    subtitle: .settingsLocationSharingSubtitle(partnerName),
                    isOn: locationSharingBinding,
                    isEnabled: locationViewModel.isSharingLoaded
                )
            }
        }
    }

    // MARK: - Notifications (collapsible)

    private var notificationsSection: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: 0) {
                notificationsHeader

                if isNotificationsExpanded {
                    notificationsContent
                        .padding(.top, PaeoniaSpacing.space16)
                        .transition(.opacity)
                }
            }
        }
    }

    private var notificationsHeader: some View {
        Button {
            withAnimation(PaeoniaMotion.stateChange) {
                isNotificationsExpanded.toggle()
            }
        } label: {
            HStack(spacing: PaeoniaSpacing.space12) {
                Text(.settingsNotificationsSectionTitle)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)

                Spacer(minLength: PaeoniaSpacing.space8)

                Image(systemName: "chevron.down")
                    .font(PaeoniaTypography.button)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .rotationEffect(.degrees(isNotificationsExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: PaeoniaSpacing.buttonHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(notificationsAccessibilityValue))
    }

    /// Announces the notifications section's open/closed state to VoiceOver. Typed as
    /// a `LocalizedStringResource` so the ternary resolves the generated symbols
    /// without an ambiguous `Text` initializer.
    private var notificationsAccessibilityValue: LocalizedStringResource {
        isNotificationsExpanded
            ? .settingsNotificationsExpandedLabel
            : .settingsNotificationsCollapsedLabel
    }

    private var notificationsContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            settingRow(
                title: .settingsNotificationsPartnerAnsweredTitle,
                subtitle: .settingsNotificationsPartnerAnsweredSubtitle(partnerName),
                isOn: notificationBinding(.partnerAnswered),
                isEnabled: viewModel.isLoaded
            )

            settingRow(
                title: .settingsNotificationsDailyChallengeTitle,
                subtitle: .settingsNotificationsDailyChallengeSubtitle(partnerName),
                isOn: notificationBinding(.dailyChallenge),
                isEnabled: viewModel.isLoaded
            )

            settingRow(
                title: .settingsNotificationsStreakRemindersTitle,
                subtitle: .settingsNotificationsStreakRemindersSubtitle,
                isOn: notificationBinding(.streakReminders),
                isEnabled: viewModel.isLoaded
            )

            settingRow(
                title: .settingsNotificationsWidgetAlertsTitle,
                subtitle: .settingsNotificationsWidgetAlertsSubtitle(partnerName),
                isOn: notificationBinding(.widgetUpdates),
                isEnabled: viewModel.isLoaded
            )

            if viewModel.systemNotificationsDenied {
                systemDisabledNote
            }
        }
    }

    private var systemDisabledNote: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Divider()
                .overlay(.paeoniaSurfacePressed)

            Text(.settingsNotificationsSystemOffTitle)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
            Text(.settingsNotificationsSystemOffMessage)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text(.settingsNotificationsOpenSettingsButton)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
        }
    }

    // MARK: - Privacy, safety, and purchases

    @ViewBuilder
    private var privacySafetySection: some View {
        if let partnerUserID {
            PaeoniaCard(padding: 0) {
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
            }
        }
    }

    private var restorePurchasesSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            sectionHeader(.settingsPurchasesSectionTitle)

            Button(action: restorePurchases) {
                Label {
                    Text(
                        viewModel.isRestoringPurchases
                            ? .settingsPurchasesRestoring
                            : .paywallRestorePurchases
                    )
                } icon: {
                    if viewModel.isRestoringPurchases {
                        ProgressView()
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .disabled(viewModel.isRestoringPurchases)
        }
    }

    // MARK: - Account actions

    /// Log out and leave-relationship sit together at the bottom as real buttons.
    /// Leaving is destructive, so it uses the destructive style and a broken-heart
    /// icon, and still only opens the confirmation alert — nothing happens until the
    /// user confirms there.
    private var accountActionsSection: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Button(action: onLogout) {
                Text(.settingsAccountLogoutButton)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())

            Button {
                isConfirmingLeave = true
            } label: {
                Label {
                    Text(.settingsUnpairButton)
                } icon: {
                    Image(systemName: "heart.slash.fill")
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(PaeoniaDestructiveButtonStyle())
            .disabled(viewModel.isLeavingRelationship)

            // Delete stays quiet so it doesn't compete with the leave button
            // above it: leaving is the likelier intent, deleting is the last resort.
            Button {
                isConfirmingDelete = true
            } label: {
                Text(.authDeleteAccountButton)
                    .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PaeoniaQuietDestructiveButtonStyle())
            .disabled(viewModel.isLeavingRelationship)
        }
        .padding(.top, PaeoniaSpacing.space24)
    }

    // MARK: - Actions

    private func leaveRelationship() {
        Task {
            let didLeave = await viewModel.leaveRelationship()
            if didLeave {
                bannerCenter.dismiss()
                onLeftRelationship()
            }
        }
    }

    private func restorePurchases() {
        Task { @MainActor in
            if await viewModel.restorePurchases() {
                await onPurchasesRestored()
            }
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
        }
    }

}

// MARK: - Building blocks

private extension SettingsView {
    func sectionHeader(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(PaeoniaTypography.sectionTitle)
            .foregroundStyle(.paeoniaTextSecondary)
    }

    /// A settings row: a title + subtitle column that keeps a comfortable gap from
    /// the trailing switch, so long copy wraps in its own column and never crowds the
    /// toggle.
    func settingRow(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        isOn: Binding<Bool>,
        isEnabled: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: PaeoniaSpacing.space16) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(title)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(subtitle)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.paeoniaAccentPrimary)
                .disabled(!isEnabled)
                .accessibilityLabel(Text(title))
        }
    }

    func notificationBinding(_ kind: NotificationPreferenceKind) -> Binding<Bool> {
        Binding(
            get: {
                switch kind {
                case .streakReminders:
                    viewModel.streakRemindersEnabled
                case .dailyChallenge:
                    viewModel.dailyChallengeEnabled
                case .partnerAnswered:
                    viewModel.partnerAnsweredEnabled
                case .widgetUpdates:
                    viewModel.widgetAlertsEnabled
                }
            },
            set: { newValue in
                Task { await viewModel.setNotificationPreference(kind, enabled: newValue) }
            }
        )
    }

    var locationSharingBinding: Binding<Bool> {
        Binding(
            get: { locationViewModel.sharingEnabled },
            set: { newValue in
                Task { await locationViewModel.setSharingEnabled(newValue) }
            }
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView(locationViewModel: LocationMapViewModel(), partnerName: "Oda")
    }
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
