import Foundation

/// Text the inviter typed for a first day question but has not sent yet, by question
/// version. After pairing, the daily answer screen takes it for the question that
/// version became (`DailyChallengeViewModel.adoptFirstDayDrafts`). It belongs to no
/// couple, so an ended relationship's purge keeps it and only sign-out clears it.
@MainActor
protocol FirstDayAnswerDraftStoring: AnyObject {
    func texts(for userID: UUID) -> [UUID: String]
    func setText(_ text: String, for questionVersionID: UUID, userID: UUID)
    func clearText(for questionVersionID: UUID, userID: UUID)
    func clearAll(for userID: UUID)
}

extension FirstDayAnswerDraftStoring {
    /// Returns the text and removes it, so it is used once.
    func takeText(for questionVersionID: UUID, userID: UUID) -> String? {
        guard let text = texts(for: userID)[questionVersionID] else {
            return nil
        }
        clearText(for: questionVersionID, userID: userID)
        return text
    }
}

@MainActor
final class UserDefaultsFirstDayAnswerDraftStore: FirstDayAnswerDraftStoring {
    static let shared = UserDefaultsFirstDayAnswerDraftStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for userID: UUID) -> String {
        "paeonia.firstDay.answerDrafts.\(userID.uuidString)"
    }

    func texts(for userID: UUID) -> [UUID: String] {
        let stored = defaults.dictionary(forKey: key(for: userID)) as? [String: String] ?? [:]
        return stored.reduce(into: [:]) { result, entry in
            if let versionID = UUID(uuidString: entry.key) {
                result[versionID] = entry.value
            }
        }
    }

    /// Blank text removes the entry.
    func setText(_ text: String, for questionVersionID: UUID, userID: UUID) {
        var current = texts(for: userID)
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        current[questionVersionID] = hasContent ? text : nil
        persist(current, for: userID)
    }

    func clearText(for questionVersionID: UUID, userID: UUID) {
        var current = texts(for: userID)
        current[questionVersionID] = nil
        persist(current, for: userID)
    }

    func clearAll(for userID: UUID) {
        defaults.removeObject(forKey: key(for: userID))
    }

    private func persist(_ texts: [UUID: String], for userID: UUID) {
        guard !texts.isEmpty else {
            defaults.removeObject(forKey: key(for: userID))
            return
        }
        defaults.set(
            Dictionary(uniqueKeysWithValues: texts.map { ($0.key.uuidString, $0.value) }),
            forKey: key(for: userID)
        )
    }
}
