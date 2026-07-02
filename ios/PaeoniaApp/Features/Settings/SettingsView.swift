import SwiftUI
import UIKit

/// The "Me" tab: the couple member's personal corner. Hosts location sharing,
/// notification settings (collapsed by default to stay compact), and the account
/// actions — log out and leave the relationship.
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
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
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.openURL) private var openURL

    /// Gates the leave action behind a centered confirmation alert, so the pairing
    /// can never end on a single stray tap.
    @State private var isConfirmingLeave = false
    /// The notifications block is collapsed by default so the tab stays short; the
    /// user opens it when they want to change an alert.
    @State private var isNotificationsExpanded = false

    @MainActor
    init(
        locationViewModel: LocationMapViewModel,
        partnerName: String,
        onLeftRelationship: @escaping () -> Void = {},
        onLogout: @escaping () -> Void = {}
    ) {
        self.locationViewModel = locationViewModel
        self.partnerName = partnerName
        self.onLeftRelationship = onLeftRelationship
        self.onLogout = onLogout
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                locationSection
                notificationsSection
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
