import CryptoKit
import Foundation

/// The last time today's question opened on this phone, by any route: the couple day
/// (`yyyy-MM-dd`) and whether the partner had answered by then.
nonisolated struct TodaysQuestionOpening: Codable, Equatable {
    let day: String
    let partnerHadAnswered: Bool

    /// Why today's question opens by itself on `day`, or nil when it doesn't. It opens once
    /// a couple day, and once more when the partner has answered since it last opened.
    static func occasion(
        on day: String, partnerHasAnswered: Bool, after last: TodaysQuestionOpening?
    ) -> Occasion? {
        guard let last, last.day == day else { return .firstOfDay }
        return !last.partnerHadAnswered && partnerHasAnswered ? .partnerAnswered : nil
    }

    enum Occasion: Equatable {
        /// It has not opened yet this couple day.
        case firstOfDay
        /// It opened today before the partner answered, and the partner has answered since.
        case partnerAnswered
    }
}

/// Remembers the last opening of today's question for one user, so a plain open of the
/// app shows the question by itself at most once a day. The key holds a hash of the
/// user ID, so UserDefaults does not store the account ID in plain text.
nonisolated struct TodaysQuestionOpeningStore {
    private static let keyPrefix = "paeonia.todaysQuestion.lastOpening.v1."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastOpening(userID: UUID) -> TodaysQuestionOpening? {
        guard let data = defaults.data(forKey: key(userID: userID)) else { return nil }
        return try? PropertyListDecoder().decode(TodaysQuestionOpening.self, from: data)
    }

    func record(_ opening: TodaysQuestionOpening, userID: UUID) {
        defaults.set(try? PropertyListEncoder().encode(opening), forKey: key(userID: userID))
    }

    private func key(userID: UUID) -> String {
        let digest = SHA256.hash(data: Data(userID.uuidString.lowercased().utf8))
        return Self.keyPrefix + digest.paeoniaHexString
    }
}
