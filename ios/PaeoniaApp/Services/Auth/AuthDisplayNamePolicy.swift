import Foundation

nonisolated enum AuthDisplayNamePolicy {
    static func normalizedFirstName(from value: String) -> String? {
        guard let displayName = value.trimmedNonEmpty else {
            return nil
        }

        return displayName
            .split(whereSeparator: \.isWhitespace)
            .first
            .map { String($0.prefix(80)) }
    }

    static func validatedSingleName(from value: String) -> String? {
        guard let displayName = value.trimmedNonEmpty else {
            return nil
        }

        let parts = displayName.split(whereSeparator: \.isWhitespace)
        guard parts.count == 1, let name = parts.first else {
            return nil
        }

        return String(name.prefix(80))
    }
}
