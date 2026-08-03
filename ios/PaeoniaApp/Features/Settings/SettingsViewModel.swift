import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    enum Notice: Equatable {
        case saveFailed
        case leaveFailed
        case purchasesRestored
        case noPurchasesToRestore
        case restorePurchasesFailed
    }

    private let preferences: (any NotificationPreferencesProviding)?
    private let authorization: any PushAuthorizationProviding
    private let pairingService: (any PairingServicing)?
    private let operationProvider: any PairingClientOperationProviding
    private let storeKitService: any PaeoniaStoreKitServicing

    /// Notification toggles default to the server defaults (on) until the real
    /// values load, so controls never flicker off.
    private(set) var streakRemindersEnabled = true
    private(set) var dailyChallengeEnabled = true
    private(set) var partnerAnsweredEnabled = true
    private(set) var widgetAlertsEnabled = true
    private(set) var memoriesEnabled = true
    private(set) var isLoaded = false
    /// True when the user has turned notifications off in iOS Settings, so the
    /// in-app toggle can explain why nothing arrives.
    private(set) var systemNotificationsDenied = false
    /// True while the leave-relationship request is in flight, so the button can
    /// disable and avoid a double tap.
    private(set) var isLeavingRelationship = false
    private(set) var isRestoringPurchases = false
    private(set) var notice: Notice?

    init(
        preferences: (any NotificationPreferencesProviding)? = NotificationPreferencesServiceFactory.makeDefault(),
        authorization: any PushAuthorizationProviding = PushAuthorizationService(),
        pairingService: (any PairingServicing)? = nil,
        operationProvider: (any PairingClientOperationProviding)? = nil,
        userID: String? = nil,
        storeKitService: (any PaeoniaStoreKitServicing)? = nil
    ) {
        self.preferences = preferences
        self.authorization = authorization
        self.pairingService = pairingService ?? (try? SupabasePairingService.live())
        self.operationProvider = operationProvider ?? PairingClientOperationFactory.shared
        self.storeKitService = storeKitService ?? PaeoniaStoreKitService.shared
        if let userID {
            self.storeKitService.configure(userID: userID)
        }
    }

    func load() async {
        systemNotificationsDenied = await authorization.isDenied()

        guard let preferences else {
            isLoaded = true
            return
        }

        do {
            apply(try await preferences.loadNotificationPreferences())
        } catch {
            // Keep the optimistic default visible; the next save still works.
        }
        isLoaded = true
    }

    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled: Bool) async {
        guard enabled != value(for: kind) else {
            return
        }

        let previous = value(for: kind)
        setLocalValue(enabled, for: kind)

        guard let preferences else {
            return
        }

        do {
            try await preferences.setNotificationPreference(kind, enabled: enabled)
        } catch {
            setLocalValue(previous, for: kind)
            notice = .saveFailed
        }
    }

    /// Ends the current pairing from the You tab. On success the root re-resolves
    /// access and the user lands back in the unpaired flow; the caller is
    /// responsible for asking the root to refresh.
    func leaveRelationship() async -> Bool {
        guard let pairingService else {
            notice = .leaveFailed
            return false
        }

        isLeavingRelationship = true
        defer { isLeavingRelationship = false }

        do {
            let operation = operationProvider.makeOperation()
            _ = try await pairingService.leaveRelationship(operation: operation)
            return true
        } catch {
            notice = .leaveFailed
            return false
        }
    }

    func restorePurchases() async -> Bool {
        guard !isRestoringPurchases else {
            return false
        }

        isRestoringPurchases = true
        notice = nil
        defer { isRestoringPurchases = false }

        do {
            let restored = try await storeKitService.restorePurchases()
            notice = restored ? .purchasesRestored : .noPurchasesToRestore
            return restored
        } catch {
            notice = .restorePurchasesFailed
            return false
        }
    }

    func dismissNotice() {
        notice = nil
    }

    private func apply(_ preferences: NotificationPreferences) {
        streakRemindersEnabled = preferences.streakRemindersEnabled
        dailyChallengeEnabled = preferences.dailyChallengeEnabled
        partnerAnsweredEnabled = preferences.partnerAnsweredEnabled
        widgetAlertsEnabled = preferences.widgetUpdatesEnabled
        memoriesEnabled = preferences.memoriesEnabled
    }

    private func value(for kind: NotificationPreferenceKind) -> Bool {
        switch kind {
        case .streakReminders:
            streakRemindersEnabled
        case .dailyChallenge:
            dailyChallengeEnabled
        case .partnerAnswered:
            partnerAnsweredEnabled
        case .widgetUpdates:
            widgetAlertsEnabled
        case .memories:
            memoriesEnabled
        }
    }

    private func setLocalValue(_ enabled: Bool, for kind: NotificationPreferenceKind) {
        switch kind {
        case .streakReminders:
            streakRemindersEnabled = enabled
        case .dailyChallenge:
            dailyChallengeEnabled = enabled
        case .partnerAnswered:
            partnerAnsweredEnabled = enabled
        case .widgetUpdates:
            widgetAlertsEnabled = enabled
        case .memories:
            memoriesEnabled = enabled
        }
    }
}
