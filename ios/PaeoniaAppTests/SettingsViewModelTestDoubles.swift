import Foundation
import StoreKit
@testable import PaeoniaApp

// Test doubles for SettingsViewModelTests.

enum SettingsFakePreferencesError: Error {
    case failed
}

// An actor supplies the async-ness, so the sync bodies need no `async`/`await`.
actor SettingsFakeNotificationPreferences {
    private var preferences: NotificationPreferences
    private var failOnSet: Bool
    private var failOnLoad: Bool
    private let holdSets: Bool
    private var heldSets = [CheckedContinuation<Void, Never>]()
    private var holdsLoads = false
    private var heldLoads = [CheckedContinuation<Void, Never>]()
    private let updates = AsyncStream<NotificationPreferences>.makeStream()
    private(set) var setCallCount = 0
    private(set) var lastSetKind: NotificationPreferenceKind?
    private(set) var lastSetValue: Bool?
    /// Every value that reached the "server", in arrival order.
    private(set) var sentValues = [Bool]()
    /// Every question time that reached the "server", in arrival order.
    private(set) var sentQuestionTimes = [QuestionTimeReminder]()

    init(
        preferences: NotificationPreferences = NotificationPreferences(),
        failOnSet: Bool = false,
        failOnLoad: Bool = false,
        holdSets: Bool = false
    ) {
        self.preferences = preferences
        self.failOnSet = failOnSet
        self.failOnLoad = failOnLoad
        self.holdSets = holdSets
    }

    func setFailing(_ failing: Bool) {
        failOnSet = failing
    }

    func setLoadFailing(_ failing: Bool) {
        failOnLoad = failing
    }

    func setLoadHolding(_ holding: Bool) {
        holdsLoads = holding
    }

    var heldLoadCount: Int {
        heldLoads.count
    }

    func releaseLoads() {
        heldLoads.forEach { $0.resume() }
        heldLoads = []
    }

    func releaseNextSet() {
        guard !heldSets.isEmpty else {
            return
        }
        heldSets.removeFirst().resume()
    }

    nonisolated func notificationPreferenceUpdates() -> AsyncStream<NotificationPreferences> {
        updates.stream
    }

    func emit(_ value: NotificationPreferences) {
        updates.continuation.yield(value)
    }

    var heldSetCount: Int {
        heldSets.count
    }

    func releaseSets() {
        heldSets.forEach { $0.resume() }
        heldSets = []
    }

    /// Returns the values as they were when the read started, like a real
    /// request that is slow to come back.
    func loadNotificationPreferences() async throws -> NotificationPreferences {
        let snapshot = preferences
        if holdsLoads {
            await withCheckedContinuation { heldLoads.append($0) }
        }
        if failOnLoad {
            throw SettingsFakePreferencesError.failed
        }
        return snapshot
    }

    func setQuestionTimeReminder(_ reminder: QuestionTimeReminder) async throws {
        setCallCount += 1
        if holdSets {
            await withCheckedContinuation { heldSets.append($0) }
        }
        if failOnSet {
            throw SettingsFakePreferencesError.failed
        }
        sentQuestionTimes.append(reminder)
        preferences.questionTime = reminder
    }

    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled value: Bool) async throws {
        setCallCount += 1
        if holdSets {
            await withCheckedContinuation { heldSets.append($0) }
        }
        if failOnSet {
            throw SettingsFakePreferencesError.failed
        }
        lastSetKind = kind
        lastSetValue = value
        sentValues.append(value)
        store(value, for: kind)
    }

    private func store(_ value: Bool, for kind: NotificationPreferenceKind) {
        switch kind {
        case .streakReminders:
            preferences.streakRemindersEnabled = value
        case .dailyChallenge:
            preferences.dailyChallengeEnabled = value
        case .partnerAnswered:
            preferences.partnerAnsweredEnabled = value
        case .messages:
            preferences.messagesEnabled = value
        case .widgetUpdates:
            preferences.widgetUpdatesEnabled = value
        case .memories:
            preferences.memoriesEnabled = value
        case .games:
            preferences.gamesEnabled = value
        case .dateReminders:
            preferences.dateRemindersEnabled = value
        }
    }
}

extension SettingsFakeNotificationPreferences: NotificationPreferencesProviding {}

struct SettingsFakePushAuthorization: PushAuthorizationProviding {
    var denied = false

    func requestAuthorizationIfNeeded() -> Bool { true }

    func isDenied() -> Bool {
        denied
    }
}

