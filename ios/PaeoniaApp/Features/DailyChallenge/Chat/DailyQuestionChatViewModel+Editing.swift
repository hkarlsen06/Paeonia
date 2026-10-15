import Foundation

// MARK: - Editing

extension DailyQuestionChatViewModel {
    func canEdit(_ message: DailyQuestionChatMessage) -> Bool {
        message.canEdit(by: participants.currentUserID)
    }

    /// One edit at a time. Switching would throw away the changes typed so far.
    func startEditing(_ message: DailyQuestionChatMessage) {
        guard canEdit(message), editTarget == nil else { return }
        replyTarget = nil
        editTarget = message
        composerFocusRequest += 1
        Task { await presence.stopTyping() }
    }

    func cancelEdit() {
        editTarget = nil
    }

    /// Saves the new text of `editTarget`. The live message query shows the change on
    /// both phones once the server has it.
    func saveEdit(_ text: String) async -> EditOutcome {
        guard let target = editTarget else { return .saved }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return .failed }
        guard body.unicodeScalars.count <= Self.maximumMessageLength else {
            notice = .messageTooLong
            return .failed
        }
        guard body != target.body else {
            editTarget = nil
            return .saved
        }
        do {
            try await service.editMessage(messageID: target.id, body: body)
            editTarget = nil
            PaeoniaHaptics.selection()
            return .saved
        } catch is DailyQuestionChatEditWindowClosedError {
            editTarget = nil
            notice = .editWindowClosed
            return .windowClosed
        } catch {
            notice = .editFailed(PaeoniaFailure(error))
            return .failed
        }
    }
}
