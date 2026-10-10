import Foundation

/// Convex returns one row as an object. Functions ported from SQL
/// `returns table` return an array. This accepts both and keeps the first row.
nonisolated struct FirstRow<Row: Decodable>: Decodable {
    let row: Row?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            row = nil
        } else if let rows = try? container.decode([Row].self) {
            row = rows.first
        } else {
            row = try container.decode(Row.self)
        }
    }
}
