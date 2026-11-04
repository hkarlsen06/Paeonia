import Foundation

nonisolated enum PiccanteRules {
    static func keepsSelection(from previous: RemotePiccanteGame?, to next: RemotePiccanteGame?) -> Bool {
        guard let previous, let next else { return false }
        return previous.id == next.id && previous.gameNumber == next.gameNumber
            && previous.phase == next.phase && previous.turnUserID == next.turnUserID
            && previous.bites == next.bites
    }

    static func validNote(_ note: String) -> Bool {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.unicodeScalars.count <= 60
            && !trimmed.unicodeScalars.contains {
                let category = $0.properties.generalCategory
                return category == .control || category == .lineSeparator || category == .paragraphSeparator
            }
    }
    static func canBite(_ tile: Int, in game: RemotePiccanteGame, userID: UUID) -> Bool {
        game.phase == .biting && game.turnUserID == userID && tile >= 0 && tile < (game.size ?? 0) * (game.size ?? 0)
            && !game.bites.contains { $0.tile == tile }
    }
    static func canSniff(_ tile: Int, in game: RemotePiccanteGame, userID: UUID) -> Bool {
        canBite(tile, in: game, userID: userID) && game.mySniff == nil && game.myChili != tile
    }
    static func cappedNote(_ note: String) -> String {
        let scalars = note.unicodeScalars.filter {
            let category = $0.properties.generalCategory
            return category != .control && category != .lineSeparator && category != .paragraphSeparator
        }
        return String(String.UnicodeScalarView(scalars.prefix(60)))
    }

    static func variety(gameID: UUID, number: Int, tile: Int) -> PiccanteVariety {
        let seed = gameID.uuidString.utf8.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1) }
        let offset = Int((seed &+ UInt64(number &* 17)) % 10)
        // Stepping four through nine varieties keeps neighboring pieces distinct at every box size.
        return PiccanteVariety.allCases[(offset + tile * 4) % PiccanteVariety.allCases.count]
    }
}
