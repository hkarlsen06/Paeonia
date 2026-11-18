import Foundation

/// What Home tells this person before the couple's access ends, so losing it is never a surprise.
/// Access itself still ends when the server says so.
nonisolated enum AccessNotice: Equatable, Sendable {
    /// Apple could not take this person's subscription payment and keeps trying during the grace
    /// period. Only the person who pays sees it. The server shows the partner plain `active`.
    /// `graceEndsAt` is when Apple stops trying, which tells one failed payment from the next.
    case paymentProblem(graceEndsAt: Date?)
    /// The couple's access ends on `endsAt` because nobody's subscription renews. `canRenew` is true
    /// for the person who pays, who can turn renewal back on. The partner's notice names nobody.
    case ending(endsAt: Date, canRenew: Bool)
    /// This person's subscription has run another half-year and renews on `renewsAt`. The law asks
    /// for this reminder, with how to cancel, at least every six months. Only the person who pays
    /// sees it. `dueAt` is when the half-year passed, which tells one reminder from the next.
    case running(renewsAt: Date, dueAt: Date)

    /// How many days before the end the notice shows. The server pushes on the same day
    /// (`ENDING_NOTICE_DAYS` in `backend/convex/lib/subscriptionNotices.ts`).
    static let endingNoticeDays = 5

    /// One half-year of a subscription, counted from its first purchase, and how many days after
    /// it passes the reminder shows. The server pushes by the same two numbers
    /// (`RUNNING_NOTICE_PERIOD_DAYS` and `RUNNING_NOTICE_WINDOW_DAYS` in `subscriptionNotices.ts`).
    static let runningNoticePeriodDays = 180
    static let runningNoticeWindowDays = 14

    /// Names this notice, so closing it on Home hides only this one. A new end date or another
    /// failed payment gives a new id, and the notice shows again.
    var id: String {
        switch self {
        case let .paymentProblem(graceEndsAt):
            "paymentProblem-" + (graceEndsAt?.formatted(.iso8601) ?? "unknown")
        case let .ending(endsAt, _):
            "ending-" + endsAt.formatted(.iso8601)
        case let .running(_, dueAt):
            "running-" + dueAt.formatted(.iso8601)
        }
    }

    init?(user: RemoteUserEntitlement?, couple: RemoteCoupleEntitlement?, now: Date) {
        let paysThroughAppStore = user?.isEntitled == true && user?.source == "storekit"
        // Hidden only while someone else keeps the couple's access going without a payment problem.
        if paysThroughAppStore, user?.status == "grace",
           couple == nil || couple?.coveringUserID == user?.userID || couple?.status == "grace" {
            self = .paymentProblem(graceEndsAt: user?.currentPeriodEnd)
            return
        }
        if couple?.isEntitled == true, let endsAt = couple?.accessEndsAt,
           now < endsAt, now >= endsAt.addingTimeInterval(-Double(Self.endingNoticeDays) * 86_400) {
            self = .ending(endsAt: endsAt, canRenew: paysThroughAppStore)
            return
        }
        // A subscription that ends or has a failed payment got its own notice above.
        guard paysThroughAppStore, user?.status == "active", user?.willRenew == true,
              let subscribedSince = user?.subscribedSince, let renewsAt = user?.currentPeriodEnd,
              let dueAt = Self.runningNoticeDue(subscribedSince: subscribedSince, now: now)
        else { return nil }
        self = .running(renewsAt: renewsAt, dueAt: dueAt)
    }

    /// When the half-year reminder that shows at `now` came due, for a subscription first bought
    /// at `subscribedSince`. Nil in the first half-year and once the days it shows for are over.
    static func runningNoticeDue(subscribedSince: Date, now: Date) -> Date? {
        let period = Double(runningNoticePeriodDays) * 86_400
        let halfYears = (now.timeIntervalSince(subscribedSince) / period).rounded(.down)
        guard halfYears >= 1 else { return nil }
        let dueAt = subscribedSince.addingTimeInterval(halfYears * period)
        return now < dueAt.addingTimeInterval(Double(runningNoticeWindowDays) * 86_400) ? dueAt : nil
    }
}
