import Foundation

extension Sequence where Element == UInt8 {
    /// Lowercase hex digits for each byte. Works on `Data` and on CryptoKit digests.
    nonisolated var paeoniaHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
