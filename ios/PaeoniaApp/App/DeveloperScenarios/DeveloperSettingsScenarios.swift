#if DEBUG
  import SwiftUI

  @MainActor
  struct DeveloperSettingsScenarioView: View {
    let scenario: DeveloperScenario

    var body: some View {
      switch scenario {
      case .notificationPrimer:
        PushPermissionPrimerView(
          ask: .afterSharing,
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
            dataExportService: nil,
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
            partnerUserID: DeveloperScenarioFixture.partnerUserID,
            relationshipStartedOn: "2025-09-14",
            locationViewModel: locationViewModel,
            partnerName: "Robin",
            ownAccess: partnerPays ? .nothing : .appStoreSubscription,
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
        storeKitService: DeveloperScenarioStoreKitService(isInFreeTrial: !partnerPays),
        loadAccessSnapshot: { [partnerPays] in
          partnerPays ? Self.partnerPaysSnapshot : DeveloperScenarioFixture.subscriptionSnapshot
        }
      )
    }

    /// Robin's yearly subscription, so Alex has nothing of their own.
    private nonisolated static let partnerPaysSnapshot = RemoteAccessSnapshot(
      userEntitlement: nil,
      coupleEntitlement: RemoteCoupleEntitlement(
        coupleID: DeveloperScenarioFixture.coupleID,
        isEntitled: true,
        coveringUserID: DeveloperScenarioFixture.partnerUserID,
        source: "storekit",
        status: "active",
        productID: nil,
        billingPeriod: "yearly",
        currentPeriodEnd: DeveloperScenarioFixture.now.addingTimeInterval(200 * 86_400),
        updatedAt: DeveloperScenarioFixture.now
      ),
      relationshipState: nil
    )

    /// Robin's subscription covers Alex, who has none of their own.
    private var partnerPays: Bool {
      scenario == .settingsPartnerPays
    }

    private var locationViewModel: LocationMapViewModel {
      LocationMapViewModel(
        visibilityStore: InMemoryLocationVisibilityRepository(),
        ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
        pendingOperationStore: InMemoryPendingSyncOperationRepository(),
        operationProvider: DeveloperScenarioOperationProvider(),
        locationCapture: DeveloperUnavailableLocationCapture()
      )
    }
  }

  actor DeveloperNotificationPreferences: NotificationPreferencesProviding {
    private var preferences = NotificationPreferences()

    func loadNotificationPreferences() throws -> NotificationPreferences { preferences }

    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled: Bool) throws {
      preferences[kind] = enabled
    }

    func setQuestionTimeReminder(_ reminder: QuestionTimeReminder) throws {
      preferences.questionTime = reminder
    }
  }

  @MainActor
  private final class DeveloperUnavailableLocationCapture: ForegroundLocationCapturing {
    func captureCurrentLocation() throws -> LocationPoint {
      throw ForegroundLocationCaptureError.unavailable
    }
  }
#endif
