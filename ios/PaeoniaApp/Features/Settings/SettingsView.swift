import SwiftUI
import UIKit

/// The "You" tab: the couple member's personal corner. For MVP it hosts the
/// notification settings; more personal settings will join it here.
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    let locationViewModel: LocationMapViewModel
    /// The partner's display name, so location/notification copy names the partner
    /// instead of saying "your partner".
    let partnerName: String
    /// Called after the couple is successfully unpaired, so the root can re-resolve
    /// access and move the user back to the unpaired flow.
    let onLeftRelationship: () -> Void
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.openURL) private var openURL

    /// Gates the leave action behind a centered confirmation alert, so the pairing
    /// can never end on a single stray tap.
    @State private var isConfirmingLeave = false

    @MainActor
    init(
        locationViewModel: LocationMapViewModel,
        partnerName: String,
        onLeftRelationship: @escaping () -> Void = {}
    ) {
        self.locationViewModel = locationViewModel
        self.partnerName = partnerName
        self.onLeftRelationship = onLeftRelationship
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                locationSection
                notificationsSection
                leaveRelationshipSection
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

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.settingsLocationSectionTitle)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextSecondary)

            PaeoniaCard {
                Toggle(isOn: locationSharingBinding) {
                    VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                        Text(.settingsLocationSharingTitle)
                            .font(PaeoniaTypography.body)
                            .foregroundStyle(.paeoniaTextPrimary)
                        Text(.settingsLocationSharingSubtitle(partnerName))
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                }
                .tint(.paeoniaAccentPrimary)
                .disabled(!locationViewModel.isSharingLoaded)
            }
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.settingsNotificationsSectionTitle)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextSecondary)

            PaeoniaCard {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                    notificationToggle(
                        isOn: notificationBinding(.partnerAnswered),
                        title: .settingsNotificationsPartnerAnsweredTitle,
                        subtitle: .settingsNotificationsPartnerAnsweredSubtitle(partnerName)
                    )

                    notificationToggle(
                        isOn: notificationBinding(.dailyChallenge),
                        title: .settingsNotificationsDailyChallengeTitle,
                        subtitle: .settingsNotificationsDailyChallengeSubtitle(partnerName)
                    )

                    notificationToggle(
                        isOn: notificationBinding(.streakReminders),
                        title: .settingsNotificationsStreakRemindersTitle,
                        subtitle: .settingsNotificationsStreakRemindersSubtitle
                    )

                    notificationToggle(
                        isOn: notificationBinding(.widgetUpdates),
                        title: .settingsNotificationsWidgetAlertsTitle,
                        subtitle: .settingsNotificationsWidgetAlertsSubtitle(partnerName)
                    )

                    if viewModel.systemNotificationsDenied {
                        systemDisabledNote
                    }
                }
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

    /// The leave action lives at the very bottom, understated and unframed, so it
    /// reads as a deliberate exit rather than an ordinary setting. Tapping it only
    /// opens the confirmation alert; nothing happens until the user confirms there.
    private var leaveRelationshipSection: some View {
        Button {
            isConfirmingLeave = true
        } label: {
            Text(.settingsUnpairButton)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaError)
                .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLeavingRelationship)
        .padding(.top, PaeoniaSpacing.space24)
    }

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

    private func notificationToggle(
        isOn: Binding<Bool>,
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(title)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(subtitle)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .tint(.paeoniaAccentPrimary)
        .disabled(!viewModel.isLoaded)
    }

    private func notificationBinding(_ kind: NotificationPreferenceKind) -> Binding<Bool> {
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

    private var locationSharingBinding: Binding<Bool> {
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
