import Foundation

/// A JSON tree that ConvexMobile can decode any query result into.
///
/// ConvexMobile decodes with a plain `JSONDecoder` and offers no way to change
/// it. That decoder cannot read the ISO-8601 date strings our DTOs use, and it
/// can reject whole-number doubles for `Int` fields. The transport therefore
/// subscribes with this type, calls `normalizedData()`, and the service decodes
/// that text with `PaeoniaConvexClient.decoder`.
nonisolated enum LiveJSON: Decodable, Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([LiveJSON])
    case object([String: LiveJSON])

    init(from decoder: any Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: AnyKey.self) {
            if let tagged = Self.taggedNumber(in: keyed) {
                self = tagged
                return
            }
            var object: [String: LiveJSON] = [:]
            for key in keyed.allKeys {
                object[key.stringValue] = try keyed.decode(LiveJSON.self, forKey: key)
            }
            self = .object(object)
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var items: [LiveJSON] = []
            while !unkeyed.isAtEnd {
                items.append(try unkeyed.decode(LiveJSON.self))
            }
            self = .array(items)
            return
        }

        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else {
            self = .number(try single.decode(Double.self))
        }
    }

    /// JSON text where every whole number is written without a fraction
    /// (`5`, not `5.0`), so `Int` DTO fields always decode. Other numbers keep
    /// their fraction.
    func normalizedData() throws -> Data {
        try JSONSerialization.data(withJSONObject: foundationValue, options: [.fragmentsAllowed])
    }

    private var foundationValue: Any {
        switch self {
        case .null:
            NSNull()
        case let .bool(value):
            value
        case let .integer(value):
            value
        case let .number(value):
            // 2^53 is the largest range where every integer is exact in a Double.
            if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
                Int64(value)
            } else {
                value
            }
        case let .string(value):
            value
        case let .array(items):
            items.map(\.foundationValue)
        case let .object(object):
            object.mapValues(\.foundationValue)
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }

    /// Convex wraps int64 and special doubles in single-key tagged objects.
    private static func taggedNumber(in keyed: KeyedDecodingContainer<AnyKey>) -> LiveJSON? {
        guard keyed.allKeys.count == 1, let key = keyed.allKeys.first,
              let encoded = try? keyed.decode(String.self, forKey: key)
        else {
            return nil
        }
        switch key.stringValue {
        case "$integer":
            return int64(from: encoded).map { .integer($0) }
        case "$float":
            return double(from: encoded).map { .number($0) }
        default:
            return nil
        }
    }

    private static func int64(from base64: String) -> Int64? {
        guard let data = Data(base64Encoded: base64), data.count == 8 else {
            return nil
        }
        return data.withUnsafeBytes { Int64(littleEndian: $0.loadUnaligned(as: Int64.self)) }
    }

    private static func double(from base64: String) -> Double? {
        guard let data = Data(base64Encoded: base64), data.count == 8 else {
            return nil
        }
        return data.withUnsafeBytes { Double(bitPattern: UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self))) }
    }
}
