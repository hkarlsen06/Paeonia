import Foundation

/// The note's length rule, the same as the server's (`parseLetterBody` in
/// `backend/convex/lib/letters.ts`), so the phone never offers to send a note the server
/// refuses. The note loses the white space JavaScript's `trim` removes at either end, then
/// counts code points, so "❤️" counts two. Change the two together.
nonisolated enum LetterBody {
    static let maxLength = 2_000

    /// JavaScript's white space and line terminators. U+FEFF is one of them, and U+0085 is not.
    private static let trimmedScalars: Set<Unicode.Scalar> = {
        let codes: [UInt32] = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F]
            + [0x3000, 0xFEFF] + Array(UInt32(0x2000)...UInt32(0x200A))
        return Set(codes.compactMap(Unicode.Scalar.init))
    }()

    /// The note as the server stores it.
    static func trimmed(_ body: String) -> String {
        let scalars = body.unicodeScalars
        guard let first = scalars.firstIndex(where: { !trimmedScalars.contains($0) }),
              let last = scalars.lastIndex(where: { !trimmedScalars.contains($0) })
        else { return "" }
        return String(scalars[first...last])
    }

    /// How much of the limit the note uses.
    static func length(_ body: String) -> Int {
        trimmed(body).unicodeScalars.count
    }

    static func canSend(_ body: String) -> Bool {
        (1...maxLength).contains(length(body))
    }

    /// `body`, cut at a whole character so that it fits the limit. Used while typing and pasting.
    static func limited(_ body: String) -> String {
        guard length(body) > maxLength else { return body }
        var fits = 0
        var tooLong = body.count
        while tooLong - fits > 1 {
            let middle = (fits + tooLong) / 2
            if length(String(body.prefix(middle))) <= maxLength {
                fits = middle
            } else {
                tooLong = middle
            }
        }
        return String(body.prefix(fits))
    }
}
