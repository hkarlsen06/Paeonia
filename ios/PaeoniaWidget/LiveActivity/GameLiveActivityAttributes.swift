import ActivityKit
import Foundation

/// The Live Activity that shows the partner's game session and whose turn it is. The server starts,
/// updates and ends it with pushes (`buildLiveActivityApsPayload` in
/// `backend/convex/lib/apns.ts`). iOS decodes those pushes into these types with the default
/// JSON coding, so the property and case names are the push's keys and values.
nonisolated struct GameLiveActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var gameKind: Game
        var phase: Phase
        var turn: Turn
    }

    /// Every game, with the raw values of `GameKind`.
    nonisolated enum Game: String, Codable, Hashable, Sendable, CaseIterable {
        case ludo = "ludo"
        case drawAndGuess = "draw_and_guess"
        case connectFour = "connect_four"
        case mindMeld = "mind_meld"
        case consensio = "consensio"
        case guessMySpot = "guess_my_spot"
        case dotsAndBoxes = "dots_and_boxes"
        case ultimateTicTacToe = "ultimate_tic_tac_toe"
        case piccante = "piccante"
        case storyChain = "story_chain"
        case exquisiteCorpse = "exquisite_corpse"

        /// The deep link path, as in `GameKind.path`: `paeonia://games/<path>`.
        var path: String {
            rawValue.replacingOccurrences(of: "_", with: "-")
        }
    }

    nonisolated enum Phase: String, Codable, Hashable, Sendable {
        case playing
        case ended
    }

    /// Whose turn it is in the game, from this person's side. `none` while nothing waits for either.
    nonisolated enum Turn: String, Codable, Hashable, Sendable {
        case yours
        case theirs
        case none
    }

    /// The server's id for this activity. The phone registers the activity's push token under it.
    var activityID: String
    /// What this person calls their partner. Empty when the partner has no name.
    var partnerName: String
}
