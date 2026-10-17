import Foundation
import Observation

/// Each paired person's answer to "Help us improve Paeonia?", which decides
/// whether `PaeoniaAnalytics` counts their use. The server keeps the answer, so
/// it is the same on every phone and there is a record of what was agreed to.
///
/// A yes starts PostHog only once the server has saved it. A no stops it on
/// this phone at once. An answer the server has not saved yet stays on the
/// phone and wins over what the server says, so a no given offline is never
/// undone by an older yes.
@MainActor
@Observable
final class UsageSharingModel {
    /// Names the question and privacy policy version a person answered.
    /// Change it when either changes in a way that needs a new answer.
    static let noticeVersion = "2026-10-18"

    nonisolated private struct SetArgs: Encodable, Sendable {
        let shares: Bool
        let notice: String

        enum CodingKeys: String, CodingKey {
            case shares = "p_shares"
            case notice = "p_notice"
        }
    }

    nonisolated private struct ServerAnswer: Decodable, Sendable {
        let sharesUsage: Bool?

        enum CodingKeys: String, CodingKey {
            case sharesUsage = "shares_usage"
        }
    }

    /// The paired person whose answer this is, or nil while nobody is paired.
    private(set) var userID: String?
    /// Their answer, or nil before it is known.
    private(set) var shares: Bool?
    /// The server confirmed that this person has not answered yet.
    private(set) var isUnanswered = false
    /// One answer is on its way to the server. Later answers wait for it.
    private var isSending = false
    /// Changes on every follow, answer and read, so a read that comes back after
    /// any of them is ignored.
    private var generation = 0

    private let defaults: UserDefaults
    private static let unsentKey = "analytics.unsentUsageAnswers"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Asks the question once Home is on screen.
    var needsAnswer: Bool {
        PaeoniaAnalytics.isAvailable && userID != nil && shares == nil && isUnanswered
    }

    /// Follows the paired person, or nobody when `userID` is nil. Nothing is
    /// counted until the server's answer, or an unsent one, is known.
    func follow(_ userID: String?) async {
        guard userID != self.userID else {
            return
        }
        self.userID = userID
        generation &+= 1
        shares = nil
        isUnanswered = false
        PaeoniaAnalytics.share(as: nil)
        guard let userID else {
            return
        }
        if let unsent = unsentAnswers()[userID] {
            // A yes waits for the server. A no is already in effect.
            shares = unsent
            await sendUnsent(for: userID)
        } else {
            await refresh()
        }
    }

    /// Reads the answer again, because it may have changed on another phone.
    /// Runs when the person is followed and each time the app comes to the front.
    func refresh() async {
        guard let userID else {
            return
        }
        // An answer the server does not have yet goes first, and wins.
        guard unsentAnswers()[userID] == nil else {
            await sendUnsent(for: userID)
            return
        }
        generation &+= 1
        let readGeneration = generation
        guard !isSending,
              let client = try? PaeoniaConvexClientProvider.shared.client(),
              let answer: ServerAnswer = try? await client.query("analytics:get_usage_sharing"),
              // The person changed, answered, or a newer read started meanwhile.
              readGeneration == generation, userID == self.userID, !isSending
        else {
            return
        }
        guard let serverShares = answer.sharesUsage else {
            shares = nil
            isUnanswered = true
            PaeoniaAnalytics.share(as: nil)
            return
        }
        isUnanswered = false
        shares = serverShares
        if serverShares {
            PaeoniaAnalytics.share(as: userID)
        } else {
            // This phone may still hold data from a yes withdrawn elsewhere.
            PaeoniaAnalytics.stopSharingAndDeleteQueued()
        }
    }

    /// Saves the paired person's answer. Saying no stops sharing at once, and
    /// after a yes the server asks PostHog to delete what it has.
    func answer(_ shares: Bool) async {
        guard let userID else {
            return
        }
        await answer(shares, for: userID)
    }

    /// Saves the answer of the signed-in person `userID`, who may not be paired
    /// yet, as on the last page of profile setup.
    func answer(_ shares: Bool, for userID: String) async {
        var unsent = unsentAnswers()
        unsent[userID] = shares
        saveUnsent(unsent)
        if userID == self.userID {
            let withdrew = self.shares == true && !shares
            generation &+= 1
            self.shares = shares
            isUnanswered = false
            if withdrew {
                PaeoniaAnalytics.stopSharingAndDeleteQueued()
            } else if !shares {
                PaeoniaAnalytics.share(as: nil)
            }
        }
        await sendUnsent(for: userID)
    }

    /// Sends the newest unsent answer, one request at a time. A yes takes effect
    /// once the server has it. A failed send stays on the phone for next time.
    private func sendUnsent(for userID: String) async {
        guard !isSending, let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return
        }
        isSending = true
        defer { isSending = false }
        while let answer = unsentAnswers()[userID] {
            do {
                try await client.mutation(
                    "analytics:set_usage_sharing",
                    args: SetArgs(shares: answer, notice: Self.noticeVersion)
                )
            } catch {
                return
            }
            var unsent = unsentAnswers()
            guard unsent[userID] == answer else {
                // A newer answer came in while this one was out. Send it too.
                continue
            }
            unsent[userID] = nil
            saveUnsent(unsent)
            if answer, userID == self.userID {
                PaeoniaAnalytics.share(as: userID)
            }
        }
    }

    private func unsentAnswers() -> [String: Bool] {
        defaults.dictionary(forKey: Self.unsentKey) as? [String: Bool] ?? [:]
    }

    private func saveUnsent(_ answers: [String: Bool]) {
        defaults.set(answers, forKey: Self.unsentKey)
    }
}
