import Foundation

/// What Home tells this person before the couple's access ends, so losing it is never a surprise.
/// Access itself still ends when the server says so.
nonisolated enum AccessNotice: Equatable, Sendable {
    /// Apple could not take this person's subscription payment and keeps trying during the grace
    /// period. Only the person who pays sees it. The server shows the partner plain `active`.
    case paymentProblem
    /// The couple's access ends on `endsAt` because nobody's subscription renews. `canRenew` is true
    /// for the person who pays, who can turn renewal back on. The partner's notice names nobody.
    case ending(endsAt: Date, canRenew: Bool)

    /// How many days before the end the notice shows. The server pushes on the same day
    /// (`ENDING_NOTICE_DAYS` in `backend/convex/lib/subscriptionNotices.ts`).
    static let endingNoticeDays = 5

    init?(user: RemoteUserEntitlement?, couple: RemoteCoupleEntitlement?, now: Date) {
        let paysThroughAppStore = user?.isEntitled == true && user?.source == "storekit"
        // Hidden only while someone else keeps the couple's access going without a payment problem.
        if paysThroughAppStore, user?.status == "grace",
           couple == nil || couple?.coveringUserID == user?.userID || couple?.status == "grace" {
            self = .paymentProblem
            return
        }
        guard couple?.isEntitled == true, let endsAt = couple?.accessEndsAt,
              now < endsAt, now >= endsAt.addingTimeInterval(-Double(Self.endingNoticeDays) * 86_400)
        else { return nil }
        self = .ending(endsAt: endsAt, canRenew: paysThroughAppStore)
    }
}
