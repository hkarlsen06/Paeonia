import SwiftUI
import UIKit

/// Everything Paeonia can tell you about, grouped by who it comes from.
///
/// Each switch saves on its own. A failed save puts the switch back and the Us tab
/// shows the banner, so the screen never claims a setting stuck when it did not.
struct NotificationSettingsView: View {
    let viewModel: SettingsViewModel
    /// Names the partner in the copy instead of saying "your partner".
    let partnerName: String

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Group {
                // A blocked system setting or a failed load explains every switch
                // below it, so it goes first.
                switch viewModel.systemNotificationPermission {
                case .denied:
                    systemDisabledNote
                case .notAsked:
                    systemNotAskedNote
                case .allowed:
                    if case let .failed(failure) = viewModel.notificationLoadState {
                        loadFailedNote(failure)
                    }
                }

                partnerSection
                remindersSection
                lockScreenSection
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .paeoniaGroupedList()
        .navigationTitle(Text(.settingsNotificationsSectionTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadNotificationSettings()
        }
        .task {
            await viewModel.observeNotificationSettings()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                return
            }
            Task {
                await viewModel.refreshSystemNotificationStatus()
            }
        }
    }

    private var partnerSection: some View {
        Section {
            toggleRow(
                .dailyChallenge,
                title: .settingsNotificationsDailyChallengeTitle,
                subtitle: .settingsNotificationsDailyChallengeSubtitle(partnerName)
            )
            // Covers both the daily "answered too" push and the Topics push.
            toggleRow(
                .partnerAnswered,
                title: .settingsNotificationsPartnerAnsweredTitle,
                subtitle: .settingsNotificationsPartnerAnsweredSubtitle(partnerName)
            )
            // Covers chats on questions and on memories.
            toggleRow(
                .messages,
                title: .dailyChatNotificationsTitle,
                subtitle: .dailyChatNotificationsSubtitle(partnerName)
            )
            toggleRow(
                .widgetUpdates,
                title: .settingsNotificationsWidgetAlertsTitle,
                subtitle: .settingsNotificationsWidgetAlertsSubtitle(partnerName)
            )
            toggleRow(
                .memories,
                title: .settingsNotificationsMemoriesTitle,
                subtitle: .settingsNotificationsMemoriesSubtitle(partnerName)
            )
            toggleRow(
                .games,
                title: .settingsNotificationsGamesTitle,
                subtitle: .settingsNotificationsGamesSubtitle(partnerName)
            )
        } header: {
            Text(.settingsNotificationsPartnerSectionTitle(partnerName))
        }
    }

    private var remindersSection: some View {
        Section {
            toggleRow(
                .streakReminders,
                title: .settingsNotificationsStreakRemindersTitle,
                subtitle: .settingsNotificationsStreakRemindersSubtitle
            )
            questionTimeRows
        } header: {
            Text(.settingsNotificationsRemindersSectionTitle)
        }
    }

    /// Applies only when iOS hides previews on the lock screen. The default keeps everything hidden.
    private var lockScreenSection: some View {
        Section {
            toggleRow(
                .lockScreenDetails,
                title: .settingsNotificationsLockScreenDetailsTitle,
                subtitle: .settingsNotificationsLockScreenDetailsSubtitle(partnerName)
            )
        } header: {
            Text(.settingsNotificationsLockScreenSectionTitle)
        }
    }

    /// The switch, and the time picker once it is on. The picker shows the time in the
    /// phone's own format. The reminder uses the time zone of the phone used last.
    @ViewBuilder
    private var questionTimeRows: some View {
        Toggle(
            isOn: Binding(
                get: { viewModel.questionTime.isEnabled },
                set: { newValue in
                    Task { await viewModel.setQuestionTime(isEnabled: newValue) }
                }
            )
        ) {
            Text(.settingsNotificationsQuestionTimeTitle)
            Text(.settingsNotificationsQuestionTimeSubtitle)
        }
        .disabled(!viewModel.isNotificationSettingsLoaded)

        if viewModel.questionTime.isEnabled {
            DatePicker(
                selection: Binding(
                    get: { viewModel.questionTime.time(on: Date()) },
                    set: { newValue in
                        Task {
                            await viewModel.setQuestionTime(minutes: QuestionTimeReminder.minutes(of: newValue))
                        }
                    }
                ),
                displayedComponents: .hourAndMinute
            ) {
                Text(.settingsNotificationsQuestionTimeTimeLabel)
            }
            .disabled(!viewModel.isNotificationSettingsLoaded)
        }
    }

    private func toggleRow(
        _ kind: NotificationPreferenceKind,
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { viewModel.isEnabled(kind) },
                set: { newValue in
                    Task { await viewModel.setNotificationPreference(kind, enabled: newValue) }
                }
            )
        ) {
            Text(title)
            Text(subtitle)
        }
        .disabled(!viewModel.isNotificationSettingsLoaded)
    }

    /// Turning a switch on here does nothing while iOS has notifications off for
    /// Paeonia, so say that plainly and offer the way to fix it.
    private var systemDisabledNote: some View {
        noteCard(
            systemImage: "bell.slash.fill",
            title: .settingsNotificationsSystemOffTitle,
            message: .settingsNotificationsSystemOffMessage,
            buttonTitle: .settingsNotificationsOpenSettingsButton
        ) {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                openURL(url)
            }
        }
    }

    /// iOS has never asked, so nothing can arrive yet. Ask now with the real
    /// system prompt instead of sending the user to the Settings app.
    private var systemNotAskedNote: some View {
        noteCard(
            systemImage: "bell.badge",
            title: .settingsNotificationsSystemNotAskedTitle,
            message: .settingsNotificationsSystemNotAskedMessage,
            buttonTitle: .settingsNotificationsTurnOnButton,
            isBusy: viewModel.isRequestingSystemPermission
        ) {
            Task {
                await viewModel.requestSystemNotificationPermission()
            }
        }
    }

    /// Only a phone without a connection is told to check it.
    private func loadFailedNote(_ failure: PaeoniaFailure) -> some View {
        noteCard(
            systemImage: failure == .offline ? "wifi.exclamationmark" : "exclamationmark.circle",
            title: .settingsNotificationsLoadFailedTitle,
            message: failure == .offline
                ? .settingsNotificationsLoadFailedMessage
                : .settingsNotificationsLoadFailedLaterMessage,
            buttonTitle: .commonTryAgain
        ) {
            Task {
                await viewModel.loadNotificationSettings()
            }
        }
    }

    private func noteCard(
        systemImage: String,
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        buttonTitle: LocalizedStringResource,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    Text(title)
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)
                    Text(message)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: systemImage)
            }

            Button(action: action) {
                Text(buttonTitle)
            }
            .disabled(isBusy)
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(viewModel: SettingsViewModel(), partnerName: "Oda")
    }
    .preferredColorScheme(.dark)
}
