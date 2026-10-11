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

    /// Turns whatever the user typed or pasted into the characters a code field should
    /// show. A Paeonia join link (alone or inside a shared message) gives its code.
    /// Anything else is uppercased, mapped like `normalized` (I and L become 1, O
    /// becomes 0), stripped of characters outside the code alphabet, and cut to `length`.
    static func entryText(_ raw: String) -> String {
        if let code = joinLinkCode(in: raw) {
            return code
        }

        var text = ""
        for character in raw.uppercased() {
            let mapped = canonicalCharacter(character)
            if allowedCharacters.contains(mapped) {
                text.append(mapped)
            }
            if text.count == length {
                break
            }
        }
        return text
    }

    private static func joinLinkCode(in text: String) -> String? {
        for token in text.split(whereSeparator: \.isWhitespace) {
            let trimmed = token.trimmingCharacters(in: .punctuationCharacters)
            if let url = URL(string: trimmed), let code = PairingJoinURL.inviteCode(from: url) {
                return code
            }
        }
        return nil
    }

    private static func canonicalCharacter(_ character: Character) -> Character {
        switch character {
        case "I", "L": "1"
        case "O": "0"
        default: character
        }
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

    private static let webScheme = "https"
    private static let appScheme = "paeonia"

    static func make(inviteCode rawInviteCode: String) throws -> URL {
        let inviteCode = try PairingInviteCode.normalized(rawInviteCode)
        var components = URLComponents()
        components.scheme = webScheme
        components.host = host
        components.path = "/\(joinPathComponent)/\(inviteCode)"

        guard let url = components.url else {
            throw PairingInviteCodeError.invalidJoinURL
        }

        return url
    }

    /// Manual recovery URL used by the web fallback when Safari keeps a
    /// same-domain Universal Link in the browser. Shared invites still use the
    /// canonical HTTPS URL; this scheme is only an explicit "Open Paeonia" action.
    static func makeAppURL(inviteCode rawInviteCode: String) throws -> URL {
        let inviteCode = try PairingInviteCode.normalized(rawInviteCode)
        var components = URLComponents()
        components.scheme = appScheme
        components.host = joinPathComponent
        components.path = "/\(inviteCode)"

        guard let url = components.url else {
            throw PairingInviteCodeError.invalidJoinURL
        }

        return url
    }

    static func inviteCode(from url: URL) -> String? {
        let scheme = url.scheme?.lowercased()
        let urlHost = url.host()?.lowercased()
        let components = url.pathComponents.filter { $0 != "/" }

        if scheme == webScheme,
           urlHost == host,
           components.count == 2,
           components[0] == joinPathComponent {
            return try? PairingInviteCode.normalized(components[1])
        }

        if scheme == appScheme,
           urlHost == joinPathComponent,
           components.count == 1 {
            return try? PairingInviteCode.normalized(components[0])
        }

        return nil
    }
}
