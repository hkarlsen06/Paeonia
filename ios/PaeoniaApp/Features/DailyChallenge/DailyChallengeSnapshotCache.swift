import Foundation

// MARK: - Protocol

/// Persists the last successful `DailyChallengeRemoteSnapshotRow` so the view
/// model can seed itself synchronously on launch, before the first network load
/// returns. This removes the placeholder→content swap for returning users.
///
/// Conforms to `Sendable` so it can be injected into actors and `@MainActor`
/// types without requiring an `@unchecked` annotation at the call site.
nonisolated protocol DailyChallengeSnapshotCaching: Sendable {
    /// Returns the last-saved row for `ownerUserID`, or `nil` when no cache
    /// exists, the on-disk data is corrupt, or the schema version is stale.
    /// Always fails soft — never throws or crashes.
    func load(ownerUserID: UUID) -> DailyChallengeRemoteSnapshotRow?

    /// Persists `row` so the next cold launch can seed from it. Overwrites any
    /// previously cached row for `ownerUserID`. Silently drops write errors.
    func save(_ row: DailyChallengeRemoteSnapshotRow, ownerUserID: UUID)

    /// Deletes all cached content. Called when the user leaves the paired state
    /// (sign-out, un-pair, lost access, ended relationship) so private
    /// relationship content does not remain on the device.
    func clearAll()
}

// MARK: - File-based implementation

/// A file-backed implementation of `DailyChallengeSnapshotCaching`.
///
/// Layout:
/// - One JSON file per owner, stored under
///   `Application Support/DailyChallengeSnapshotCache/<ownerUserID-lowercase>.json`
/// - Each file encodes a versioned envelope so a future schema change can be
///   detected and the cache silently dropped instead of crashing.
/// - Dates are encoded with `.iso8601` in both directions, independent of the
///   Supabase client's own coder.
///
/// Privacy: keyed by `ownerUserID` so a different signed-in user never reads
/// another user's cached relationship content. `clearAll()` wipes the whole
/// directory and is called on sign-out / un-pair / lost access.
final class FileDailyChallengeSnapshotCache: @unchecked Sendable, DailyChallengeSnapshotCaching {
    // Bump this whenever `DailyChallengeRemoteSnapshotRow` or its nested types
    // gain a non-optional field (which would cause `JSONDecoder` to throw on
    // old cached files). Incrementing causes stale files to be treated as
    // cache misses rather than decoding errors.
    private static let currentSchemaVersion = 1

    private let directoryURL: URL

    init(directoryURL: URL = FileDailyChallengeSnapshotCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func live() -> FileDailyChallengeSnapshotCache {
        FileDailyChallengeSnapshotCache()
    }

    func load(ownerUserID: UUID) -> DailyChallengeRemoteSnapshotRow? {
        let url = fileURL(for: ownerUserID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Any decode failure (corrupt file, wrong version, schema mismatch) is
        // treated as a cache miss — never propagated to the caller.
        guard let envelope = try? decoder().decode(CacheEnvelope.self, from: data) else {
            return nil
        }
        guard envelope.schemaVersion == Self.currentSchemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            // Stale version or unexpected owner — treat as a miss and let the
            // file get overwritten on the next successful network load.
            return nil
        }
        return envelope.row
    }

    func save(_ row: DailyChallengeRemoteSnapshotRow, ownerUserID: UUID) {
        let envelope = CacheEnvelope(
            schemaVersion: Self.currentSchemaVersion,
            ownerUserID: ownerUserID,
            row: row
        )
        guard let data = try? encoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: ownerUserID), options: [.atomic])
    }

    func clearAll() {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    // MARK: Private helpers

    private func fileURL(for ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            ownerUserID.uuidString.lowercased() + ".json",
            isDirectory: false
        )
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DailyChallengeSnapshotCache", isDirectory: true)
    }

    /// The local cache uses its own date strategy (iso8601) so dates round-trip
    /// independently of the Supabase client's decoder configuration.
    private func encoder() -> JSONEncoder {
        let coder = JSONEncoder()
        coder.dateEncodingStrategy = .iso8601
        return coder
    }

    private func decoder() -> JSONDecoder {
        let coder = JSONDecoder()
        coder.dateDecodingStrategy = .iso8601
        return coder
    }
}

// MARK: - On-disk envelope

/// Versioned wrapper persisted to disk. The `schemaVersion` lets future code
/// detect and discard stale files rather than crash on decode errors.
///
/// `nonisolated` so its synthesized `Codable` conformance can be used from the
/// cache's nonisolated `load`/`save` (the module defaults to main-actor isolation,
/// the same reason the remote row types are declared `nonisolated`).
nonisolated private struct CacheEnvelope: Codable {
    let schemaVersion: Int
    let ownerUserID: UUID
    let row: DailyChallengeRemoteSnapshotRow
}
