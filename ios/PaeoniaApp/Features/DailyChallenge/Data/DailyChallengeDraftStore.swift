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

    /// One JSON blob of Codable drafts per user.
    private func key(for userID: UUID) -> String {
        "paeonia.dailyChallenge.drafts.v2.\(userID.uuidString)"
    }

    func drafts(for userID: UUID) -> [UUID: DailyAnswerDraft] {
        guard let data = defaults.data(forKey: key(for: userID)),
              let envelope = try? decoder.decode(DraftEnvelope.self, from: data)
        else {
            return [:]
        }

        return map(envelope.drafts)
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
