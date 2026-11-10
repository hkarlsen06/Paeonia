import Foundation

nonisolated enum PiccanteAction: String, Codable, CaseIterable, Sendable {
    case choose = "choose_piccante_size"
    case hide = "hide_piccante_chili"
    case bite = "bite_piccante_chocolate"
    case sniff = "sniff_piccante_chocolate"
    case rematch = "start_piccante_rematch"
    case seen = "mark_piccante_result_seen"
}

nonisolated struct PiccanteMove: Codable, Equatable, Sendable {
    let action: PiccanteAction
    let gameID: UUID
    let gameNumber: Int
    let expectedVersion: Int
    var tile: Int?
    var size: Int?
    var note: String?
}

nonisolated protocol PiccanteGateway: Sendable {
    func samplePiccanteClock() async throws -> Date
    func loadPiccante() async throws -> RemotePiccanteState
    func ensurePiccante() async throws -> RemotePiccanteState
    func sendPiccante(_ move: PiccanteMove, operation: SyncClientOperation) async throws -> RemotePiccanteState
}

nonisolated extension LiveGamesGateway: PiccanteGateway {
    func samplePiccanteClock() async throws -> Date {
        try await client.mutation("piccante:sample_piccante_clock")
    }
    func loadPiccante() async throws -> RemotePiccanteState { try await client.query("piccante:get_piccante") }
    func ensurePiccante() async throws -> RemotePiccanteState {
        try await client.mutation("piccante:ensure_piccante_game")
    }
    func sendPiccante(_ move: PiccanteMove, operation: SyncClientOperation) async throws -> RemotePiccanteState {
        try await client.mutation(
            "piccante:\(move.action.rawValue)", args: PiccanteRequest(move: move, operation: operation))
    }
}

// swiftlint:disable async_without_await
nonisolated extension UnavailableGamesGateway: PiccanteGateway {
    func samplePiccanteClock() async throws -> Date { throw Unavailable() }
    func loadPiccante() async throws -> RemotePiccanteState { throw Unavailable() }
    func ensurePiccante() async throws -> RemotePiccanteState { throw Unavailable() }
    func sendPiccante(_: PiccanteMove, operation _: SyncClientOperation) async throws -> RemotePiccanteState {
        throw Unavailable()
    }
}
// swiftlint:enable async_without_await

nonisolated private struct PiccanteRequest: Encodable {
    let move: PiccanteMove
    let operation: ClientOperationFields
    init(move: PiccanteMove, operation: SyncClientOperation) {
        self.move = move
        self.operation = ClientOperationFields(operation)
    }
    enum CodingKeys: String, CodingKey {
        case gameID = "p_game_id"
        case version = "p_expected_version"
        case tile = "p_tile"
        case size = "p_size"
        case note = "p_note"
        case number = "p_game_number"
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(move.gameID, forKey: .gameID)
        if move.action == .seen {
            try container.encode(Double(move.gameNumber), forKey: .number)
        } else {
            try container.encode(Double(move.expectedVersion), forKey: .version)
        }
        try container.encodeIfPresent(move.tile.map(Double.init), forKey: .tile)
        try container.encodeIfPresent(move.size.map(Double.init), forKey: .size)
        try container.encodeIfPresent(move.note, forKey: .note)
        try operation.encode(to: encoder)
    }
}
