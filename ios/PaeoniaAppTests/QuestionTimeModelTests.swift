import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct QuestionTimeModelTests {
    @Test func savesTheReminderBeforeAskingForPermission() async {
        let log = QuestionTimeEventLog()
        let primerStore = QuestionTimeFakePrimerStore()
        let model = makeModel(log: log, primerStore: primerStore)

        model.select(.morning)
        let saved = await model.save()

        #expect(saved == 8 * 60)
        #expect(await log.events == [
            .saved(QuestionTimeReminder(isEnabled: true, minutes: 8 * 60)),
            .askedForPermission,
        ])
        #expect(primerStore.responded)
        #expect(model.saveFailure == nil)
        #expect(!model.isSaving)
    }

    @Test func eveningIsTheDefaultChoice() async {
        let log = QuestionTimeEventLog()
        let model = makeModel(log: log)

        let saved = await model.save()

        #expect(model.choice == .evening)
        #expect(saved == QuestionTimeReminder.defaultMinutes)
    }

    @Test func failedSaveKeepsTheChoiceAndDoesNotAskForPermission() async {
        let log = QuestionTimeEventLog()
        let primerStore = QuestionTimeFakePrimerStore()
        let model = makeModel(log: log, failure: URLError(.badServerResponse), primerStore: primerStore)

        model.select(.custom)
        model.customMinutes = 21 * 60 + 30
        let saved = await model.save()

        #expect(saved == nil)
        #expect(model.saveFailure == .other)
        #expect(model.choice == .custom)
        #expect(model.chosenMinutes == 21 * 60 + 30)
        #expect(await log.events.isEmpty)
        #expect(!primerStore.responded)
        #expect(!model.isSaving)
    }

    @Test func offlineSaveIsReportedAsOffline() async {
        let model = makeModel(log: QuestionTimeEventLog(), failure: URLError(.notConnectedToInternet))

        _ = await model.save()

        #expect(model.saveFailure == .offline)
    }

    @Test func retryAfterAFailureSavesTheSameChoice() async {
        let log = QuestionTimeEventLog()
        let preferences = QuestionTimeFakePreferences(log: log, failure: URLError(.notConnectedToInternet))
        let model = QuestionTimeModel(
            preferences: preferences,
            pushAuthorization: QuestionTimeFakePushAuthorization(log: log),
            primerStore: QuestionTimeFakePrimerStore()
        )
        model.select(.lunch)
        _ = await model.save()
        model.clearSaveFailure()

        await preferences.state.setFailing(false)
        let saved = await model.save()

        #expect(saved == 12 * 60)
        #expect(model.saveFailure == nil)
    }

    @Test func permissionThatDidNotSettleLeavesThePrimerEligible() async {
        let log = QuestionTimeEventLog()
        let primerStore = QuestionTimeFakePrimerStore()
        let model = QuestionTimeModel(
            preferences: QuestionTimeFakePreferences(log: log),
            pushAuthorization: QuestionTimeFakePushAuthorization(log: log, settles: false),
            primerStore: primerStore
        )

        let saved = await model.save()

        // The reminder is saved and the step still finishes.
        #expect(saved == QuestionTimeReminder.defaultMinutes)
        #expect(!primerStore.responded)
    }

    @Test func customStartsAtThePreviousChoice() {
        let model = makeModel(log: QuestionTimeEventLog())

        model.select(.lunch)
        model.select(.custom)

        #expect(model.customMinutes == 12 * 60)
        #expect(model.chosenMinutes == 12 * 60)
    }

    @Test func missingServiceReportsAFailure() async {
        let model = QuestionTimeModel(
            preferences: nil,
            pushAuthorization: QuestionTimeFakePushAuthorization(log: QuestionTimeEventLog()),
            primerStore: QuestionTimeFakePrimerStore()
        )

        let saved = await model.save()

        #expect(saved == nil)
        #expect(model.saveFailure == .other)
    }

    private func makeModel(
        log: QuestionTimeEventLog,
        failure: URLError? = nil,
        primerStore: QuestionTimeFakePrimerStore = QuestionTimeFakePrimerStore()
    ) -> QuestionTimeModel {
        QuestionTimeModel(
            preferences: QuestionTimeFakePreferences(log: log, failure: failure),
            pushAuthorization: QuestionTimeFakePushAuthorization(log: log),
            primerStore: primerStore
        )
    }
}

// MARK: - Test doubles

// swiftlint:disable async_without_await unavailable_function

enum QuestionTimeEvent: Equatable {
    case saved(QuestionTimeReminder)
    case askedForPermission
}

actor QuestionTimeEventLog {
    private(set) var events: [QuestionTimeEvent] = []

    func append(_ event: QuestionTimeEvent) {
        events.append(event)
    }
}

actor QuestionTimeFakeFailureState {
    private(set) var failure: URLError?

    init(failure: URLError?) {
        self.failure = failure
    }

    func setFailing(_ failing: Bool) {
        failure = failing ? URLError(.notConnectedToInternet) : nil
    }
}

struct QuestionTimeFakePreferences: NotificationPreferencesProviding {
    let log: QuestionTimeEventLog
    let state: QuestionTimeFakeFailureState

    init(log: QuestionTimeEventLog, failure: URLError? = nil) {
        self.log = log
        state = QuestionTimeFakeFailureState(failure: failure)
    }

    func loadNotificationPreferences() async throws -> NotificationPreferences {
        fatalError("The question time step does not load preferences")
    }

    func setNotificationPreference(_ kind: NotificationPreferenceKind, enabled: Bool) async throws {
        fatalError("The question time step only saves the reminder")
    }

    func setQuestionTimeReminder(_ reminder: QuestionTimeReminder) async throws {
        if let failure = await state.failure {
            throw failure
        }
        await log.append(.saved(reminder))
    }
}

struct QuestionTimeFakePushAuthorization: PushAuthorizationProviding {
    let log: QuestionTimeEventLog
    var settles = true

    func requestAuthorizationIfNeeded() async -> Bool {
        await log.append(.askedForPermission)
        return settles
    }

    func isDenied() async -> Bool {
        false
    }
}

final class QuestionTimeFakePrimerStore: PushPermissionPrimerPersisting {
    private(set) var responded = false

    func hasResponded() -> Bool {
        responded
    }

    func markResponded() {
        responded = true
    }
}

// swiftlint:enable async_without_await unavailable_function
