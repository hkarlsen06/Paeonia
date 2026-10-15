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
        case restorePurchasesFailed(PaeoniaFailure)
        case purchaseLinkedToAnotherAccount
    }

    /// What iOS allows. The switches only matter once iOS allows notifications.
    nonisolated enum SystemNotificationPermission: Equatable {
        case allowed
        /// iOS has never asked, for example after "Not now" on the app's own
        /// primer. The screen offers to ask now.
        case notAsked
        /// The user said no in iOS. Only the Settings app can change it.
        case denied
    }

    enum SubscriptionDetailsState: Equatable {
        case loading
        case loaded(SubscriptionDetails)
        /// The first load failed. Details already shown stay on screen instead.
        case failed(PaeoniaFailure)
    }

    enum NotificationLoadState: Equatable {
        case loading
        case loaded
        /// The first load failed and no live value has arrived yet. The switches
        /// stay disabled so they never show a guess as if it were saved.
        case failed(PaeoniaFailure)
    }

    private let preferences: (any NotificationPreferencesProviding)?
    private let authorization: any PushAuthorizationProviding
    private let pairingService: (any PairingServicing)?
    private let operationProvider: any PairingClientOperationProviding
    private let storeKitService: any PaeoniaStoreKitServicing
    private let loadAccessSnapshot: (@Sendable () async throws -> RemoteAccessSnapshot)?

    /// What the switches show. Starts at the server defaults (all on) so nothing
    /// flickers off while the real values load.
    private(set) var notificationPreferences = NotificationPreferences()
    private(set) var notificationLoadState = NotificationLoadState.loading
    private(set) var systemNotificationPermission = SystemNotificationPermission.allowed
    private(set) var isRequestingSystemPermission = false
    /// True while the leave-relationship request is in flight, so the button can
    /// disable and avoid a double tap.
    private(set) var isLeavingRelationship = false
    private(set) var isRestoringPurchases = false
    private(set) var subscriptionDetailsState = SubscriptionDetailsState.loading
    private(set) var notice: Notice?

    /// The last value the server reported or accepted for each switch. A failed
    /// save puts the switch back to this, not to whatever it showed before the tap.
    private var confirmedPreferences = NotificationPreferences()
    /// Switches with a save running. Each kind has at most one request in flight,
    /// so rapid taps can never reach the server out of order.
    private var savingKinds = Set<NotificationPreferenceKind>()
    /// True while a question time save is running. The switch and the time save together,
    /// so they share one request in flight.
    private var isSavingQuestionTime = false
    /// Goes up whenever newer server values arrive: a live update or a save the
    /// server accepted. A one-shot read that started earlier is then ignored.
    private var serverValuesRevision = 0

    init(
        preferences: (any NotificationPreferencesProviding)? = NotificationPreferencesServiceFactory.makeDefault(),
        authorization: any PushAuthorizationProviding = PushAuthorizationService(),
        pairingService: (any PairingServicing)? = nil,
        operationProvider: (any PairingClientOperationProviding)? = nil,
        userID: String? = nil,
        storeKitService: (any PaeoniaStoreKitServicing)? = nil,
        loadAccessSnapshot: (@Sendable () async throws -> RemoteAccessSnapshot)? = nil
    ) {
        self.preferences = preferences
        self.authorization = authorization
        self.pairingService = pairingService ?? (try? RemotePairingService.live())
        self.operationProvider = operationProvider ?? PairingClientOperationFactory.shared
        self.storeKitService = storeKitService ?? PaeoniaStoreKitService.shared
        self.loadAccessSnapshot = loadAccessSnapshot
            ?? (try? LiveAccessGateway(client: PaeoniaConvexClientProvider.shared.client())).map { gateway in
                { try await gateway.loadAccessSnapshot() }
            }
        if let userID {
            self.storeKitService.configure(userID: userID)
        }
    }

    var isNotificationSettingsLoaded: Bool {
        notificationLoadState == .loaded
    }

    func isEnabled(_ kind: NotificationPreferenceKind) -> Bool {
        notificationPreferences[kind]
    }

    var questionTime: QuestionTimeReminder {
        notificationPreferences.questionTime
    }

    func loadNotificationSettings() async {
        await refreshSystemNotificationStatus()

        guard let preferences else {
            notificationLoadState = .loaded
            return
        }

        if case .failed = notificationLoadState {
            notificationLoadState = .loading
        }

        let revision = serverValuesRevision
        do {
            let values = try await preferences.loadNotificationPreferences()
            // A live update or a finished save while this read was in flight is
            // newer than what the read saw, so the read's result is stale.
            guard revision == serverValuesRevision else {
                return
            }
            applyServerValues(values)
        } catch {
            // Keep the last values the server sent. Only a screen that never got
            // real values says it could not load them.
            if notificationLoadState != .loaded {
                notificationLoadState = .failed(PaeoniaFailure(error))
            }
        }
    }

    /// The user may come back from iOS Settings with notifications turned on, so
    /// the screen re-checks whenever the app becomes active.
    func refreshSystemNotificationStatus() async {
        if await authorization.isDenied() {
            systemNotificationPermission = .denied
        } else if await authorization.isNotDetermined() {
            systemNotificationPermission = .notAsked
        } else {
            systemNotificationPermission = .allowed
        }
    }

    /// Shows the real iOS permission prompt. APNs registration already runs on
    /// every app activation, so only the permission itself is missing here.
    func requestSystemNotificationPermission() async {
        guard systemNotificationPermission == .notAsked, !isRequestingSystemPermission else {
            return
        }

        isRequestingSystemPermission = true
        defer { isRequestingSystemPermission = false }

        await authorization.requestAuthorizationIfNeeded()
        await refreshSystemNotificationStatus()
    }

    /// Applies preference changes from the server (another device, defaults).
    /// Runs until the screen's task is cancelled.
    func observeNotificationSettings() async {
        guard let preferences else {
            return
        }
        for await latest in preferences.notificationPreferenceUpdates() {
            applyServerValues(latest)
        }
    }

    /// Shows the new value at once and saves it. While a save for the same switch
    /// is running, later taps only update the shown value; the running save sends
    /// the newest value once its current request finishes. That keeps one request
    /// per switch in flight, so the server always ends on the last tap.
    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled: Bool) async {
        guard enabled != notificationPreferences[kind] else {
            return
        }

        notificationPreferences[kind] = enabled

        guard let preferences else {
            confirmedPreferences[kind] = enabled
            return
        }

        guard savingKinds.insert(kind).inserted else {
            return
        }
        defer { savingKinds.remove(kind) }

        while notificationPreferences[kind] != confirmedPreferences[kind] {
            let desired = notificationPreferences[kind]
            do {
                try await preferences.setNotificationPreference(kind, enabled: desired)
                confirmedPreferences[kind] = desired
                serverValuesRevision += 1
            } catch {
                notificationPreferences[kind] = confirmedPreferences[kind]
                notice = .saveFailed
                return
            }
        }
    }

    /// Turns the question time reminder on or off, or moves its time. Follows the same rules as
    /// `setNotificationPreference`: the screen shows the new value at once, one request is in
    /// flight, and a failed save puts back the last value the server confirmed.
    func setQuestionTime(isEnabled: Bool? = nil, minutes: Int? = nil) async {
        var reminder = notificationPreferences.questionTime
        reminder.isEnabled = isEnabled ?? reminder.isEnabled
        reminder.minutes = minutes ?? reminder.minutes
        guard reminder != notificationPreferences.questionTime else {
            return
        }

        notificationPreferences.questionTime = reminder

        guard let preferences else {
            confirmedPreferences.questionTime = reminder
            return
        }

        guard !isSavingQuestionTime else {
            return
        }
        isSavingQuestionTime = true
        defer { isSavingQuestionTime = false }

        while notificationPreferences.questionTime != confirmedPreferences.questionTime {
            let desired = notificationPreferences.questionTime
            do {
                try await preferences.setQuestionTimeReminder(desired)
                confirmedPreferences.questionTime = desired
                serverValuesRevision += 1
            } catch {
                notificationPreferences.questionTime = confirmedPreferences.questionTime
                notice = .saveFailed
                return
            }
        }
    }

    /// Ends the current pairing from the You tab. On success the root re-resolves
    /// access and the user lands back in the unpaired flow; the caller is
    /// responsible for asking the root to refresh.
    func leaveRelationship() async -> Bool {
        guard !isLeavingRelationship else {
            return false
        }

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
            if restored {
                await loadSubscriptionDetails()
            }
            return restored
        } catch PaeoniaPurchaseError.cancelled {
            // The user closed the App Store sign-in sheet. Nothing went wrong.
            return false
        } catch PaeoniaPurchaseError.purchaseLinkedToAnotherAccount {
            notice = .purchaseLinkedToAnotherAccount
            return false
        } catch {
            notice = .restorePurchasesFailed(PaeoniaFailure(error))
            return false
        }
    }

    /// Reads the server's record fresh each time the screen opens, because the
    /// screen exists so people can compare it with what Apple shows.
    func loadSubscriptionDetails() async {
        guard let loadAccessSnapshot else {
            subscriptionDetailsState = .failed(.other)
            return
        }
        do {
            subscriptionDetailsState = .loaded(SubscriptionDetails(snapshot: try await loadAccessSnapshot()))
        } catch {
            if case .loaded = subscriptionDetailsState {
                return
            }
            subscriptionDetailsState = .failed(PaeoniaFailure(error))
        }
    }

    func dismissNotice() {
        notice = nil
    }

    /// Switches with a save running keep the value the user picked. Their
    /// confirmed value still updates, so a failed save falls back to the newest
    /// server value instead of an older one.
    private func applyServerValues(_ values: NotificationPreferences) {
        serverValuesRevision += 1
        for kind in NotificationPreferenceKind.allCases {
            confirmedPreferences[kind] = values[kind]
            if !savingKinds.contains(kind) {
                notificationPreferences[kind] = values[kind]
            }
        }
        confirmedPreferences.questionTime = values.questionTime
        if !isSavingQuestionTime {
            notificationPreferences.questionTime = values.questionTime
        }
        notificationLoadState = .loaded
    }
}
