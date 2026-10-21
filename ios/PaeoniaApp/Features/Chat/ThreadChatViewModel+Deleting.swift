import Foundation

// MARK: - Taking a message back

extension ThreadChatViewModel {
    func canDelete(_ message: ThreadChatMessage) -> Bool {
        message.canDelete(by: participants.currentUserID)
    }

    /// Asks the user to confirm, since the message disappears for both of them.
    func askToDelete(_ message: ThreadChatMessage) {
        guard canDelete(message) else { return }
        deleteTarget = message
    }

    func cancelDelete() {
        deleteTarget = nil
    }

    /// Takes back the message the user confirmed. It shows as deleted at once, also offline,
    /// and the delete waits in the send queue until the phone is online. A message that
    /// never left the phone is dropped, and the partner never sees it.
    func confirmDelete() async {
        guard let target = deleteTarget, let ownerUserID = participants.currentUserID else { return }
        deleteTarget = nil
        // The list may have moved on while the question was open, for example the message
        // was sent or the partner's phone confirmed it.
        let message = messages.first { $0.id == target.id } ?? target
        guard canDelete(message) else { return }
        do {
            try await service.deleteMessage(
                ownerUserID: ownerUserID,
                message: message,
                operation: operationProvider.makeOperation()
            )
        } catch ThreadChatServiceError.stillSending {
            notice = .deleteWaiting
            return
        } catch {
            notice = .deleteFailed
            return
        }
        PaeoniaHaptics.selection()
        await readStore(ownerUserID: ownerUserID)
        syncInBackground()
    }

    /// A reply or an edit that points at a message that was taken back, by either person,
    /// has nothing left to point at. The server refuses a reply to it.
    func dropTargetsOfDeletedMessages() {
        if case let .message(target)? = replyTarget, isDeleted(target.id) { replyTarget = nil }
        if let editing = editTarget, isDeleted(editing.id) { editTarget = nil }
    }

    private func isDeleted(_ messageID: UUID) -> Bool {
        messages.first { $0.id == messageID }?.isDeleted == true
    }
}
