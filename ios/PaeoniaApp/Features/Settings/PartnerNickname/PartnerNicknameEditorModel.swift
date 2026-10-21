import Observation

/// The state and async work behind the nickname screen.
///
/// The Us tab owns one instance, so a save keeps running and still reports back if the person
/// leaves the screen. The saved nickname stays upstream in the access snapshot, which the server
/// pushes live. This model only holds what the person has typed.
@MainActor
@Observable
final class PartnerNicknameEditorModel {
    enum Event: Equatable {
        case saved(nickname: String?)
        case saveFailed(PaeoniaFailure)
    }

    private(set) var savedNickname = ""
    private(set) var typedNickname: String?
    private(set) var isSaving = false
    private(set) var event: Event?
    /// Counts successful saves, so the view can play one success haptic per save.
    private(set) var completedSaveCount = 0

    @ObservationIgnored private let gateway: (any PartnerNicknameGateway)?

    init(gateway: (any PartnerNicknameGateway)?) {
        self.gateway = gateway
    }

    /// What the field shows. Until the person types, it follows the saved nickname.
    var text: String {
        typedNickname ?? savedNickname
    }

    /// What would be saved: the typed text, trimmed. Nil clears the nickname.
    var normalizedNickname: String? {
        PartnerName.normalizedNickname(text)
    }

    var hasChanges: Bool {
        typedNickname != nil && normalizedNickname != PartnerName.normalizedNickname(savedNickname)
    }

    var isTooLong: Bool {
        normalizedNickname.map { !PartnerName.isValidNickname($0) } ?? false
    }

    var canSave: Bool {
        hasChanges && !isTooLong && !isSaving && gateway != nil
    }

    var hasSavedNickname: Bool {
        PartnerName.normalizedNickname(savedNickname) != nil
    }

    /// The saved nickname can change while the screen is open, for example when the phone first
    /// loads it or another phone sets it.
    func updateSavedNickname(_ nickname: String?) {
        savedNickname = nickname ?? ""
    }

    func setText(_ text: String) {
        guard !isSaving else {
            return
        }
        typedNickname = text
    }

    func discard() {
        guard !isSaving else {
            return
        }
        typedNickname = nil
    }

    /// Clears the saved nickname right away.
    func remove() async {
        guard !isSaving else {
            return
        }
        typedNickname = ""
        await save()
    }

    func save() async {
        guard canSave, let gateway else {
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let stored = try await gateway.setNickname(normalizedNickname)
            savedNickname = stored ?? ""
            typedNickname = nil
            completedSaveCount += 1
            event = .saved(nickname: stored)
        } catch {
            // Keep the typed text so the person can try again.
            event = .saveFailed(PaeoniaFailure(error))
        }
    }

    func consumeEvent() {
        event = nil
    }
}
