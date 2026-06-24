import Foundation

nonisolated enum PairingInviteCodeError: Error, Equatable {
    case empty
    case invalidLength
    case invalidCharacters
    case invalidJoinURL
}

nonisolated enum PairingInviteCode {
    static let length = 6

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let allowedCharacters = Set(alphabet)
    private static let separatorCharacters = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "-_"))

    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    static func generate<RNG: RandomNumberGenerator>(using generator: inout RNG) -> String {
        var code = ""
        code.reserveCapacity(length)

        while code.count < length {
            let value = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
            guard value < 224 else {
                continue
            }

            code.append(alphabet[Int(value % UInt8(alphabet.count))])
        }

        return code
    }

    static func normalized(_ rawValue: String) throws -> String {
        let value = try inviteCodeCandidate(from: rawValue)
        var normalized = ""
        normalized.reserveCapacity(value.count)

        for scalar in value.unicodeScalars {
            if separatorCharacters.contains(scalar) {
                continue
            }

            let uppercased = Character(scalar).uppercased()
            switch uppercased {
            case "I", "L":
                normalized.append("1")
            case "O":
                normalized.append("0")
            default:
                normalized.append(contentsOf: uppercased)
            }
        }

        guard !normalized.isEmpty else {
            throw PairingInviteCodeError.empty
        }

        guard normalized.count == length else {
            throw PairingInviteCodeError.invalidLength
        }

        guard normalized.allSatisfy({ allowedCharacters.contains($0) }) else {
            throw PairingInviteCodeError.invalidCharacters
        }

        return normalized
    }

    private static func inviteCodeCandidate(from rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PairingInviteCodeError.empty
        }

        guard let url = URL(string: trimmed),
              let host = url.host()?.lowercased(),
              host == PairingJoinURL.host
        else {
            return trimmed
        }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2,
              components[0] == PairingJoinURL.joinPathComponent
        else {
            throw PairingInviteCodeError.invalidJoinURL
        }

        return components[1]
    }
}

nonisolated enum PairingJoinURL {
    static let host = "paeonia.no"
    static let joinPathComponent = "join"

    private static let scheme = "https"

    static func make(inviteCode rawInviteCode: String) throws -> URL {
        let inviteCode = try PairingInviteCode.normalized(rawInviteCode)
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/\(joinPathComponent)/\(inviteCode)"

        guard let url = components.url else {
            throw PairingInviteCodeError.invalidJoinURL
        }

        return url
    }
}
