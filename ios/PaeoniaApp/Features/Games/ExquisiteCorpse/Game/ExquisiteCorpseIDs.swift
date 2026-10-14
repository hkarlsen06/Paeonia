import CryptoKit
import Foundation

/// The ids of a figure and its parts, worked out from what both phones already
/// know: the game, the figure number, the part and who draws it. A part's id is
/// the same on every launch, so its draft and its queued send name the same part,
/// and the watching partner can tell which part a live message belongs to. The
/// server takes the ids as the client's own (`p_figure_id`, `p_part_id`).
nonisolated enum ExquisiteCorpseIDs {
    static func figure(gameID: UUID, number: Int) -> UUID {
        uuid5("figure:\(gameID.uuidString.lowercased()):\(number)")
    }

    static func part(gameID: UUID, figureNumber: Int, partIndex: Int, drawerID: UUID) -> UUID {
        uuid5("part:\(gameID.uuidString.lowercased()):\(figureNumber):\(partIndex):\(drawerID.uuidString.lowercased())")
    }

    /// A name-based UUID (RFC 9562 version 5) in the game's own namespace.
    private static func uuid5(_ name: String) -> UUID {
        var data = Data(namespace)
        data.append(Data(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Fixed for the game. Changing it changes every id.
    private static let namespace: [UInt8] = [
        0x6B, 0x2D, 0x0E, 0x31, 0x9C, 0x47, 0x4E, 0x5A, 0x8F, 0x13, 0x55, 0xC2, 0x70, 0xA4, 0x19, 0xE8,
    ]
}
