import ActivityKit
import Foundation

/// The Live Activity that shows the partner has a real-time game open. The server starts,
/// updates and ends it with pushes (`buildLiveActivityApsPayload` in
/// `backend/convex/lib/apns.ts`). iOS decodes those pushes into these types with the default
/// JSON coding, so the property and case names are the push's keys and values.
nonisolated struct GameLiveActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var gameKind: Game
        var phase: Phase
    }

    /// The real-time games, with the raw values of `GameKind`.
    nonisolated enum Game: String, Codable, Hashable, Sendable, CaseIterable {
        case drawAndGuess = "draw_and_guess"
        case mindMeld = "mind_meld"
        case piccante = "piccante"

        /// The deep link path, as in `GameKind.path`: `paeonia://games/<path>`.
        var path: String {
            rawValue.replacingOccurrences(of: "_", with: "-")
        }
    }

    nonisolated enum Phase: String, Codable, Hashable, Sendable {
        case playing
        case ended
    }

    /// The server's id for this activity. The phone registers the activity's push token under it.
    var activityID: String
    /// What this person calls their partner. Empty when the partner has no name.
    var partnerName: String
}
