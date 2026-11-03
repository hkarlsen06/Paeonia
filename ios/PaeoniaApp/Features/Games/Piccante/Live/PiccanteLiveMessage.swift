import Foundation

nonisolated struct PiccanteLiveMessage: GameLiveMessage {
    static let game = "piccante"
    let gameNumber: Int
    let version: Int
    let selection: Int?
    let reaction: GameLiveReaction?
}
