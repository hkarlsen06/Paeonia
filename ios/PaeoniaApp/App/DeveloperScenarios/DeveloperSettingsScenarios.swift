#if DEBUG
  import SwiftUI

  @MainActor
  struct DeveloperSettingsScenarioView: View {
    let scenario: DeveloperScenario

    var body: some View {
      switch scenario {
      case .notificationPrimer:
        PushPermissionPrimerView(
          partnerName: "Robin",
          onEnable: {},
          onNotNow: {}
        )
      case .privacySafety:
        NavigationStack {
          PrivacySafetyView(
            partnerUserID: DeveloperScenarioFixture.partnerUserID,
            partnerName: "Robin",
            service: nil,
            operationProvider: DeveloperScenarioOperationProvider()
          )
        }
      case .reportAndLeave:
        NavigationStack {
          ReportAndLeaveView(
            partnerUserID: DeveloperScenarioFixture.partnerUserID,
            partnerName: "Robin",
            service: nil,
            operationProvider: DeveloperScenarioOperationProvider()
          )
        }
      default:
        NavigationStack {
          SettingsView(
            viewModel: settingsViewModel,
            currentUserID: DeveloperScenarioFixture.currentUserID,
            currentDisplayName: "Alex",
            currentAuthProvider: .development,
            partnerUserID: DeveloperScenarioFixture.partnerUserID,
            relationshipStartedOn: "2025-09-14",
            locationViewModel: locationViewModel,
            partnerName: "Robin",
            privacySafetyService: nil,
            privacyOperationProvider: DeveloperScenarioOperationProvider()
          )
        }
      }
    }

    private var settingsViewModel: SettingsViewModel {
      SettingsViewModel(
        preferences: DeveloperNotificationPreferences(),
        authorization: DeveloperScenarioPushAuthorization(
          denied: scenario == .settingsNotificationsDenied
        ),
        pairingService: DeveloperScenarioPairingService(mode: .failing),
        operationProvider: DeveloperScenarioOperationProvider(),
        userID: DeveloperScenarioFixture.currentUserID.uuidString,
        storeKitService: DeveloperScenarioStoreKitService()
      )
    }

    private var locationViewModel: LocationMapViewModel {
      LocationMapViewModel(
        visibilityStore: InMemoryLocationVisibilitySnapshotRepository(),
        ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
        pendingOperationStore: InMemoryPendingSyncOperationRepository(),
        operationProvider: DeveloperScenarioOperationProvider(),
        locationCapture: DeveloperScenarioUnavailableLocationCapture()
      )
    }
  }

  actor DeveloperNotificationPreferences: NotificationPreferencesProviding {
    private var preferences = NotificationPreferences()

    func loadNotificationPreferences() async throws -> NotificationPreferences { preferences }

    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled: Bool) async throws {
      switch kind {
      case .streakReminders: preferences.streakRemindersEnabled = enabled
      case .dailyChallenge: preferences.dailyChallengeEnabled = enabled
      case .partnerAnswered: preferences.partnerAnsweredEnabled = enabled
      case .widgetUpdates: preferences.widgetUpdatesEnabled = enabled
      case .memories: preferences.memoriesEnabled = enabled
      }
    }
  }

  @MainActor
  private final class DeveloperScenarioUnavailableLocationCapture: ForegroundLocationCapturing {
    func captureCurrentLocation() async throws -> LocationPoint {
      throw ForegroundLocationCaptureError.unavailable
    }
  }
#endif
