import Foundation

/// Local persistence for half-written daily answers so a partly-finished reply isn't
/// lost when the answering screen is closed and reopened — or the app is relaunched.
/// Drafts are keyed per user so one person's in-progress answer never appears in
/// another's session on a shared device.
@MainActor
protocol DailyChallengeDraftStoring: AnyObject {
    func drafts(for userID: UUID) -> [UUID: DailyAnswerDraft]
    func setDraft(_ draft: DailyAnswerDraft, for instanceID: UUID, userID: UUID)
    func clearDraft(for instanceID: UUID, userID: UUID)
}

@MainActor
final class UserDefaultsDailyChallengeDraftStore: DailyChallengeDraftStoring {
    static let shared = UserDefaultsDailyChallengeDraftStore()

    /// Bump when `DailyAnswerDraft`'s stored shape changes in a way that needs
    /// migration. New optional fields decode as nil on old data and don't need it.
    private static let schemaVersion = 1

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Current home for the Codable drafts (one JSON blob per user).
    private func key(for userID: UUID) -> String {
        "paeonia.dailyChallenge.drafts.v2.\(userID.uuidString)"
    }

    /// The original text-only store: a plain `[instanceID: text]` dictionary.
    /// Read once and folded into the new format the first time a user's drafts load.
    private func legacyTextKey(for userID: UUID) -> String {
        "paeonia.dailyChallenge.drafts.\(userID.uuidString)"
    }

    func drafts(for userID: UUID) -> [UUID: DailyAnswerDraft] {
        if let data = defaults.data(forKey: key(for: userID)),
           let envelope = try? decoder.decode(DraftEnvelope.self, from: data) {
            return map(envelope.drafts)
        }

        if let migrated = migrateLegacyTextDrafts(for: userID) {
            return migrated
        }

        return [:]
    }

    func setDraft(_ draft: DailyAnswerDraft, for instanceID: UUID, userID: UUID) {
        var current = drafts(for: userID)
        if draft.hasContent {
            current[instanceID] = draft
        } else {
            current[instanceID] = nil
        }
        persist(current, for: userID)
    }

    func clearDraft(for instanceID: UUID, userID: UUID) {
        var current = drafts(for: userID)
        current[instanceID] = nil
        persist(current, for: userID)
    }

    func clearDrafts(for userID: UUID) {
        defaults.removeObject(forKey: key(for: userID))
        defaults.removeObject(forKey: legacyTextKey(for: userID))
    }

    /// Folds any old text-only drafts into the new format, then removes the old key
    /// so the migration only runs once. Returns nil when there was nothing to migrate.
    private func migrateLegacyTextDrafts(for userID: UUID) -> [UUID: DailyAnswerDraft]? {
        guard let legacy = defaults.dictionary(forKey: legacyTextKey(for: userID)) as? [String: String] else {
            return nil
        }

        let drafts = legacy.reduce(into: [UUID: DailyAnswerDraft]()) { result, entry in
            if let instanceID = UUID(uuidString: entry.key), !entry.value.isEmpty {
                result[instanceID] = DailyAnswerDraft(text: entry.value)
            }
        }

        persist(drafts, for: userID)
        defaults.removeObject(forKey: legacyTextKey(for: userID))
        return drafts
    }

    private func persist(_ drafts: [UUID: DailyAnswerDraft], for userID: UUID) {
        guard !drafts.isEmpty else {
            defaults.removeObject(forKey: key(for: userID))
            return
        }

        let envelope = DraftEnvelope(
            schemaVersion: Self.schemaVersion,
            drafts: Dictionary(uniqueKeysWithValues: drafts.map { ($0.key.uuidString, $0.value) })
        )

        if let data = try? encoder.encode(envelope) {
            defaults.set(data, forKey: key(for: userID))
        }
    }

    private func map(_ raw: [String: DailyAnswerDraft]) -> [UUID: DailyAnswerDraft] {
        raw.reduce(into: [:]) { result, entry in
            if let instanceID = UUID(uuidString: entry.key) {
                result[instanceID] = entry.value
            }
        }
    }
}

/// Versioned container so the on-disk format can evolve as new answer kinds add
/// fields to `DailyAnswerDraft`.
private struct DraftEnvelope: Codable {
    var schemaVersion: Int
    var drafts: [String: DailyAnswerDraft]
}
