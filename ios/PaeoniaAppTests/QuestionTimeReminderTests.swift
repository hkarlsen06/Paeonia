import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct QuestionTimeReminderTests {
    private func makeViewModel(
        _ preferences: SettingsFakeNotificationPreferences
    ) -> SettingsViewModel {
        SettingsViewModel(preferences: preferences, authorization: SettingsFakePushAuthorization())
    }

    @Test func startsOffAtEightInTheEvening() {
        let reminder = QuestionTimeReminder()

        #expect(reminder.isEnabled == false)
        #expect(reminder.minutes == 20 * 60)
        #expect(NotificationPreferences().questionTime == reminder)
    }

    @Test func loadShowsTheSavedReminder() async {
        let preferences = SettingsFakeNotificationPreferences(preferences: NotificationPreferences(
            questionTime: QuestionTimeReminder(isEnabled: true, minutes: 7 * 60 + 45)
        ))
        let viewModel = makeViewModel(preferences)

        await viewModel.loadNotificationSettings()

        #expect(viewModel.questionTime == QuestionTimeReminder(isEnabled: true, minutes: 465))
    }

    @Test func turningItOnSavesTheSwitchWithTheDefaultTime() async {
        let preferences = SettingsFakeNotificationPreferences()
        let viewModel = makeViewModel(preferences)
        await viewModel.loadNotificationSettings()

        await viewModel.setQuestionTime(isEnabled: true)

        #expect(viewModel.questionTime == QuestionTimeReminder(isEnabled: true, minutes: 1_200))
        #expect(await preferences.sentQuestionTimes == [QuestionTimeReminder(isEnabled: true, minutes: 1_200)])
        #expect(viewModel.notice == nil)
    }

    @Test func changingTheTimeSavesBothValues() async {
        let preferences = SettingsFakeNotificationPreferences()
        let viewModel = makeViewModel(preferences)
        await viewModel.loadNotificationSettings()
        await viewModel.setQuestionTime(isEnabled: true)

        await viewModel.setQuestionTime(minutes: 18 * 60 + 30)

        #expect(await preferences.sentQuestionTimes.last == QuestionTimeReminder(isEnabled: true, minutes: 1_110))
        #expect(viewModel.questionTime.minutes == 1_110)
    }

    @Test func unchangedReminderSendsNothing() async {
        let preferences = SettingsFakeNotificationPreferences()
        let viewModel = makeViewModel(preferences)
        await viewModel.loadNotificationSettings()

        await viewModel.setQuestionTime(isEnabled: false, minutes: 1_200)

        #expect(await preferences.setCallCount == 0)
    }

    @Test func failedSaveRevertsAndShowsNotice() async {
        let preferences = SettingsFakeNotificationPreferences(failOnSet: true)
        let viewModel = makeViewModel(preferences)
        await viewModel.loadNotificationSettings()

        await viewModel.setQuestionTime(isEnabled: true)

        #expect(viewModel.questionTime.isEnabled == false)
        #expect(viewModel.notice == .saveFailed)
    }

    /// Quick changes of the time keep one request in flight, and the server ends on the last one.
    @Test func rapidChangesSendOneRequestAtATimeAndEndOnTheLastTime() async {
        let preferences = SettingsFakeNotificationPreferences(holdSets: true)
        let viewModel = makeViewModel(preferences)
        await viewModel.loadNotificationSettings()

        let first = Task { await viewModel.setQuestionTime(isEnabled: true) }
        await waitUntil { await preferences.heldSetCount == 1 }
        await viewModel.setQuestionTime(minutes: 19 * 60)
        await viewModel.setQuestionTime(minutes: 21 * 60)

        #expect(await preferences.setCallCount == 1)
        #expect(viewModel.questionTime.minutes == 21 * 60)

        await preferences.releaseNextSet()
        await waitUntil { await preferences.heldSetCount == 1 }
        await preferences.releaseNextSet()
        await first.value

        #expect(await preferences.sentQuestionTimes == [
            QuestionTimeReminder(isEnabled: true, minutes: 1_200),
            QuestionTimeReminder(isEnabled: true, minutes: 1_260),
        ])
        #expect(viewModel.notice == nil)
    }

    @Test func staleLiveValueDoesNotRevertASaveInFlight() async {
        let preferences = SettingsFakeNotificationPreferences(holdSets: true)
        let viewModel = makeViewModel(preferences)
        let observing = Task { await viewModel.observeNotificationSettings() }

        let saving = Task { await viewModel.setQuestionTime(isEnabled: true) }
        await waitUntil { await preferences.heldSetCount == 1 }
        await preferences.emit(NotificationPreferences(memoriesEnabled: false))
        await waitUntil { viewModel.isEnabled(.memories) == false }

        #expect(viewModel.questionTime.isEnabled)

        await preferences.releaseSets()
        await saving.value

        // Once the save finished, a change from another phone applies again.
        await preferences.emit(NotificationPreferences(
            questionTime: QuestionTimeReminder(isEnabled: false, minutes: 600)
        ))
        await waitUntil { viewModel.questionTime.minutes == 600 }
        #expect(viewModel.questionTime == QuestionTimeReminder(isEnabled: false, minutes: 600))
        observing.cancel()
    }

    @Test func pickerTimeRoundTripsThroughMinutes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        let day = Date(timeIntervalSince1970: 1_791_000_000)

        for minutes in [0, 5, 7 * 60 + 30, 20 * 60, 23 * 60 + 59] {
            let reminder = QuestionTimeReminder(isEnabled: true, minutes: minutes)
            let time = reminder.time(on: day, calendar: calendar)
            #expect(QuestionTimeReminder.minutes(of: time, calendar: calendar) == minutes)
            #expect(calendar.isDate(time, inSameDayAs: day))
        }
    }

    @Test func requestSendsTheSwitchAndMinutesAsNumbers() throws {
        let request = SetQuestionTimeReminderRequest(
            reminder: QuestionTimeReminder(isEnabled: true, minutes: 1_200)
        )

        let data = try JSONEncoder().encode(request)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["p_enabled"] as? Bool == true)
        #expect(object["p_minutes"] as? Double == 1_200)
        #expect(object.count == 2)
    }

    @Test func tappingTheReminderOpensTodaysQuestions() {
        let userInfo: [AnyHashable: Any] = [
            "type": "question_time_reminder",
            "deeplink": "paeonia://daily/today",
        ]

        #expect(PaeoniaDeepLink(notificationUserInfo: userInfo) == .dailyToday(coupleDayID: nil))
    }
}

@MainActor
private func waitUntil(_ condition: () async -> Bool) async {
    for _ in 0..<200 where !(await condition()) {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
