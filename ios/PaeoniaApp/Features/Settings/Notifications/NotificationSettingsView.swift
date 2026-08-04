import SwiftUI
import UIKit

/// Everything Paeonia can tell you about, on one screen.
///
/// Each switch saves on its own; a failed save puts the switch back and the Me tab
/// shows the banner, so the screen never claims a setting stuck when it did not.
struct NotificationSettingsView: View {
    let viewModel: SettingsViewModel
    /// Names the partner in the copy instead of saying "your partner".
    let partnerName: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsDetailScreen(title: .settingsNotificationsSectionTitle) {
            PaeoniaCard {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                    SettingsToggleRow(
                        title: .settingsNotificationsPartnerAnsweredTitle,
                        subtitle: .settingsNotificationsPartnerAnsweredSubtitle(partnerName),
                        isOn: binding(.partnerAnswered),
                        isEnabled: viewModel.isLoaded
                    )

                    SettingsToggleRow(
                        title: .dailyChatNotificationsTitle,
                        subtitle: .dailyChatNotificationsSubtitle(partnerName),
                        isOn: binding(.messages),
                        isEnabled: viewModel.isLoaded
                    )

                    SettingsToggleRow(
                        title: .settingsNotificationsDailyChallengeTitle,
                        subtitle: .settingsNotificationsDailyChallengeSubtitle(partnerName),
                        isOn: binding(.dailyChallenge),
                        isEnabled: viewModel.isLoaded
                    )

                    SettingsToggleRow(
                        title: .settingsNotificationsStreakRemindersTitle,
                        subtitle: .settingsNotificationsStreakRemindersSubtitle,
                        isOn: binding(.streakReminders),
                        isEnabled: viewModel.isLoaded
                    )

                    SettingsToggleRow(
                        title: .settingsNotificationsWidgetAlertsTitle,
                        subtitle: .settingsNotificationsWidgetAlertsSubtitle(partnerName),
                        isOn: binding(.widgetUpdates),
                        isEnabled: viewModel.isLoaded
                    )

                    SettingsToggleRow(
                        title: .settingsNotificationsMemoriesTitle,
                        subtitle: .settingsNotificationsMemoriesSubtitle(partnerName),
                        isOn: binding(.memories),
                        isEnabled: viewModel.isLoaded
                    )

                    if viewModel.systemNotificationsDenied {
                        systemDisabledNote
                    }
                }
            }
        }
    }

    /// Turning a switch on here does nothing while iOS has notifications off for
    /// Paeonia, so say that plainly and offer the way to fix it.
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

    private func binding(_ kind: NotificationPreferenceKind) -> Binding<Bool> {
        Binding(
            get: {
                switch kind {
                case .streakReminders:
                    viewModel.streakRemindersEnabled
                case .dailyChallenge:
                    viewModel.dailyChallengeEnabled
                case .partnerAnswered:
                    viewModel.partnerAnsweredEnabled
                case .messages:
                    viewModel.messagesEnabled
                case .widgetUpdates:
                    viewModel.widgetAlertsEnabled
                case .memories:
                    viewModel.memoriesEnabled
                }
            },
            set: { newValue in
                Task { await viewModel.setNotificationPreference(kind, enabled: newValue) }
            }
        )
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(viewModel: SettingsViewModel(), partnerName: "Oda")
    }
    .preferredColorScheme(.dark)
}
