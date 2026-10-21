#if WIDGET_EXTENSION
import Foundation

/// Words the Lock Screen and Home Screen widgets share.
extension LockScreenSnapshot {
    /// What the widget calls the partner: the server's nickname for them when the viewer set one,
    /// otherwise the first word of their name, otherwise "Your partner".
    var partnerFirstName: String {
        partner?.shortName ?? String(localized: .widgetLockScreenPartnerFallback)
    }
}

extension LockScreenQuestionState {
    /// The status line, such as "Alex answered! Answer to see theirs." It never has a word of an answer.
    func text(partnerName: String) -> String {
        switch self {
        case .waiting: String(localized: .widgetLockScreenQuestionWaiting)
        case .partnerAnswered: String(localized: .widgetLockScreenQuestionPartnerAnswered(partnerName))
        case .waitingForPartner: String(localized: .widgetLockScreenQuestionWaitingForPartner(partnerName))
        case .bothAnswered: String(localized: .widgetLockScreenQuestionBothAnswered)
        }
    }
}

extension LockScreenCountdown.Remaining {
    /// "Today", "Tomorrow" or "12 days".
    var text: String {
        switch self {
        case .today: String(localized: .widgetLockScreenCountdownToday)
        case .tomorrow: String(localized: .widgetLockScreenCountdownTomorrow)
        case let .days(days): String(localized: .widgetLockScreenCountdownDays(days))
        }
    }
}

extension LockScreenDateItem {
    /// "Trip to Bergen", "Your birthday" or "Alex's birthday".
    func title(partnerName: String) -> String {
        switch kind {
        case let .countdown(title): title
        case .birthday(isMine: true): String(localized: .widgetHomeCountdownBirthdayYours)
        case .birthday(isMine: false): String(localized: .widgetHomeCountdownBirthdayPartner(partnerName))
        }
    }

    /// Only the countdown title is the couple's own text. A name is not hidden on a locked phone.
    var isPrivateTitle: Bool {
        if case .countdown = kind { return true }
        return false
    }

    var symbol: String {
        switch kind {
        case .countdown: "calendar"
        case .birthday: "gift.fill"
        }
    }
}
#endif
