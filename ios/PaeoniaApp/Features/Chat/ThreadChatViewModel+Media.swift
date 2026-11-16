import Foundation

// MARK: - Attachment and voice messages

extension ThreadChatViewModel {
    /// Queues a message with attachments from the composer, already prepared, and the
    /// text as their caption.
    func send(_ text: String, attachments: [ThreadChatAttachment]) async -> Bool {
        guard attachments.allSatisfy({ DailyAnswerDraft.measuredLength(of: $0.accessibilityText ?? "") <= 10_000 })
        else { return false }
        return await send(text, attachments: attachments, replacingFailed: nil, replyTo: nil)
    }

    /// Sends a failed message again from the copies kept on this phone. A video sends from
    /// the same prepared file.
    func resendAttachments(_ message: ThreadChatMessage) async {
        let attachments = (message.attachments ?? []).filter { $0.local != nil }
        guard message.delivery == .failed, !attachments.isEmpty else { return }
        _ = await send(
            message.body,
            attachments: attachments,
            replacingFailed: message.clientOperationID,
            replyTo: message.replyTo
        )
    }

    /// Queues a voice message recorded with the composer's microphone button. The
    /// recording is read into the queued message. The composer owns its source file.
    func sendVoice(fileURL: URL, durationMs: Int, transcript: String? = nil) async -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else {
            notice = .voiceFailed
            return false
        }
        return await sendVoice(
            data: data,
            durationMs: durationMs,
            transcript: transcript,
            replacingFailed: nil,
            replyTo: replyTarget?.id
        )
    }

    /// Sends a voice message that failed again, from the copy kept on this phone.
    func resendVoice(_ message: ThreadChatMessage) async {
        guard message.delivery == .failed, let data = message.voice?.data else { return }
        _ = await sendVoice(
            data: data,
            durationMs: message.voice?.durationMs ?? 0,
            transcript: message.voice?.transcript,
            replacingFailed: message.clientOperationID,
            replyTo: message.replyTo
        )
    }

    private func sendVoice(
        data: Data,
        durationMs: Int,
        transcript: String?,
        replacingFailed failedOperationID: UUID?,
        replyTo: ThreadChatItemID?
    ) async -> Bool {
        guard let ownerUserID = participants.currentUserID, isChatAvailable else {
            notice = .unavailable
            return false
        }
        guard !isQueueing, DailyAnswerDraft.measuredLength(of: transcript ?? "") <= 10_000 else { return false }
        isQueueing = true
        defer { isQueueing = false }

        do {
            try await queue(ownerUserID: ownerUserID, replacingFailed: failedOperationID) { createThread in
                _ = try await service.queueVoiceMessage(
                    ownerUserID: ownerUserID,
                    coupleID: coupleID,
                    subject: subject,
                    threadID: threadID,
                    voice: ThreadChatVoicePayload(
                        messageID: UUID(),
                        data: data,
                        durationMs: durationMs,
                        reserveOperation: operationProvider.makeOperation(),
                        finalizeOperation: operationProvider.makeOperation(),
                        transcript: transcript
                    ),
                    createThread: createThread,
                    replyTo: replyTo,
                    operation: operationProvider.makeOperation()
                )
            }
            if failedOperationID == nil { replyTarget = nil }
            return true
        } catch {
            notice = .voiceFailed
            return false
        }
    }

    /// An attachment as the chat holds it now. Once its send is recorded, an attachment
    /// learns its uploaded id, and the server's copy of the message may replace this one.
    func currentAttachment(_ attachment: ThreadChatAttachment, of message: ThreadChatMessage) -> ThreadChatAttachment {
        guard let offset = message.attachments?.firstIndex(of: attachment),
              let current = messages.first(where: { candidate in
                  if candidate.id == message.id { return true }
                  guard let operationID = message.clientOperationID else { return false }
                  return candidate.clientOperationID == operationID
              }),
              let attachments = current.attachments, attachments.indices.contains(offset)
        else { return attachment }
        return attachments[offset]
    }
}
