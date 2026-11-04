import Foundation

nonisolated struct PiccanteResolution: Equatable, Sendable {
    var game: RemotePiccanteGame?
    var heldTile: Int?
}

nonisolated enum PiccanteResolver {
    static func resolve(state: RemotePiccanteState?, pending: [PiccanteMove], deferredResult: Int?)
        -> PiccanteResolution
    {
        guard let state else { return PiccanteResolution() }
        let hiddenResults = Set(pending.filter { $0.action == .seen || $0.action == .rematch }.map(\.gameNumber))
        let result = state.unseenResult.flatMap {
            $0.gameNumber == deferredResult || hiddenResults.contains($0.gameNumber) ? nil : $0
        }
        var game = result ?? state.game
        var held: Int?
        for move in pending {
            guard let current = game, move.gameID == current.id, move.expectedVersion == current.version else {
                continue
            }
            if move.action == .seen { continue }
            guard move.gameNumber == current.gameNumber else { continue }
            switch move.action {
            case .choose:
                game?.starterUserID = state.userID
                game?.turnUserID = state.userID
                game?.size = move.size
                game?.phase = .hiding
                game?.version += 1
            case .hide:
                game?.myChili = move.tile
                game?.myNote = move.note
                game?.phase = current.partnerHidden ? .biting : .hiding
                game?.turnUserID = current.partnerHidden ? state.userID : state.partnerUserID
                game?.version += 1
            case .bite:
                held = move.tile
            case .rematch:
                let starter = current.starterUserID == state.userID ? state.partnerUserID : state.userID
                game?.gameNumber += 1
                game?.version += 1
                game?.starterUserID = starter
                game?.turnUserID = nil
                game?.phase = .choosing
                game?.size = nil
                game?.myChili = nil
                game?.myNote = nil
                game?.mySniff = nil
                game?.partnerHidden = false
                game?.partnerSniffUsed = false
                game?.bites = []
                game?.chilis = []
                game?.winnerUserID = nil
                game?.loserUserID = nil
                game?.finishedAt = nil
            case .sniff, .seen: break
            }
        }
        return PiccanteResolution(game: game, heldTile: held)
    }
}
