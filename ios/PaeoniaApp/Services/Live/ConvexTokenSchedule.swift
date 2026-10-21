import Foundation

/// When the live socket needs its next sign-in token.
///
/// The token is replaced a minute before it expires. Each new token makes Convex re-run
/// every query the phone has subscribed to, so a refresh only happens when the old token
/// is about to run out.
nonisolated enum ConvexTokenSchedule {
    /// How long before expiry a new token is fetched.
    static let refreshLead: TimeInterval = 60
    /// The shortest wait, so a token that is already expired, or a failed fetch, does
    /// not turn into a tight loop.
    static let minimumDelay: TimeInterval = 15

    /// The time until the next refresh. A token whose expiry cannot be read is
    /// refreshed after a minute, the old session token's pace.
    static func refreshDelay(forToken token: String, now: Date) -> TimeInterval {
        guard let expiresAt = expiry(ofJWT: token) else {
            return 60
        }
        return max(expiresAt.timeIntervalSince(now) - refreshLead, minimumDelay)
    }

    /// The `exp` claim of a JWT, without checking the signature.
    static func expiry(ofJWT token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            return nil
        }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? Double
        else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }
}
