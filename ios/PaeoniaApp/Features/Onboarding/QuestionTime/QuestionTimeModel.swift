import Foundation
import Observation

/// Which onboarding moment the question time step is part of. Only the copy changes.
enum QuestionTimeStepContext {
    /// The inviter, before the partner has joined.
    case waitingForPartner
    /// After pairing.
    case paired
}

/// A time the person can pick for their question reminder.
enum QuestionTimeChoice: CaseIterable, Hashable {
    case morning
    case lunch
    case evening
    /// Opens a time picker.
    case custom

    /// Minutes after midnight for the fixed times. Evening is the server's default.
    var presetMinutes: Int? {
        switch self {
        case .morning: 8 * 60
        case .lunch: 12 * 60
        case .evening: QuestionTimeReminder.defaultMinutes
        case .custom: nil
        }
    }
}

/// Saves the question time the person picks in onboarding, then asks iOS for
/// notification permission so the reminder can show.
///
/// Saving comes first. If it fails, nothing else happens: the choice stays on screen
/// and `saveFailure` tells the step to show the banner. If the person turns
/// notifications down, the reminder stays saved and the step still finishes.
@MainActor
@Observable
final class QuestionTimeModel {
    private(set) var choice: QuestionTimeChoice = .evening
    /// The picker's time, used when `choice` is `.custom`.
    var customMinutes = QuestionTimeReminder.defaultMinutes
    private(set) var isSaving = false
    /// Set when the last save failed. The step shows it and then clears it.
    private(set) var saveFailure: PaeoniaFailure?

    private let preferences: (any NotificationPreferencesProviding)?
    private let pushAuthorization: any PushAuthorizationProviding
    private let primerStore: any PushPermissionPrimerPersisting

    init(
        preferences: (any NotificationPreferencesProviding)? = NotificationPreferencesServiceFactory.makeDefault(),
        pushAuthorization: any PushAuthorizationProviding = PushAuthorizationService(),
        primerStore: any PushPermissionPrimerPersisting = UserDefaultsPushPermissionPrimerStore()
    ) {
        self.preferences = preferences
        self.pushAuthorization = pushAuthorization
        self.primerStore = primerStore
    }

    /// The minutes after midnight the reminder will use.
    var chosenMinutes: Int {
        choice.presetMinutes ?? customMinutes
    }

    func select(_ newChoice: QuestionTimeChoice) {
        guard newChoice != choice else {
            return
        }
        // The picker opens on the time that was picked, so switching to it changes nothing yet.
        if newChoice == .custom {
            customMinutes = chosenMinutes
        }
        choice = newChoice
    }

    /// Saves the reminder, turned on at the chosen time, then asks for notification
    /// permission. Returns the saved minutes, or nil when the save failed or one is
    /// already running.
    func save() async -> Int? {
        guard !isSaving else {
            return nil
        }
        let minutes = chosenMinutes
        guard let preferences else {
            saveFailure = .other
            return nil
        }

        isSaving = true
        defer { isSaving = false }
        saveFailure = nil

        do {
            try await preferences.setQuestionTimeReminder(QuestionTimeReminder(isEnabled: true, minutes: minutes))
        } catch {
            saveFailure = PaeoniaFailure(error)
            return nil
        }

        // Asks only while iOS hasn't asked yet. Recorded once iOS has an answer, so
        // the notification primer after sharing doesn't ask again. Unrecorded if the
        // app quits mid-prompt, like the primer.
        if await pushAuthorization.requestAuthorizationIfNeeded() {
            primerStore.markResponded()
        }
        return minutes
    }

    func clearSaveFailure() {
        saveFailure = nil
    }
}
