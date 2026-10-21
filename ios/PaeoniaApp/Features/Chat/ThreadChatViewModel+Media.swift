import Foundation

// MARK: - Photo and voice messages

extension ThreadChatViewModel {
    /// Queues a message with photos from the composer, already compressed, and the
    /// text as their caption.
    func send(_ text: String, photos: [ThreadChatPhoto]) async -> Bool {
        await send(text, photos: photos, replacingFailed: nil, replyTo: nil)
    }

    /// Sends a failed photo message again from the compressed copies kept on this phone.
    func resendPhotos(_ message: ThreadChatMessage) async {
        let photos = (message.photos ?? []).compactMap { photo -> ThreadChatPhoto? in
            photo.data == nil ? nil : photo
        }
        guard message.sendFailed, !photos.isEmpty else { return }
        _ = await send(
            message.body,
            photos: photos,
            replacingFailed: message.clientOperationID,
            replyTo: message.replyTo
        )
    }

    /// Queues a voice message recorded with the composer's microphone button. The
    /// recording is read into the queued message and its file deleted.
    func sendVoice(fileURL: URL, durationMs: Int) async -> Bool {
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let data = try? Data(contentsOf: fileURL) else {
            notice = .voiceFailed
            return false
        }
        return await sendVoice(
            data: data,
            durationMs: durationMs,
            replacingFailed: nil,
            replyTo: replyTarget?.id
        )
    }

    /// Sends a voice message that failed again, from the copy kept on this phone.
    func resendVoice(_ message: ThreadChatMessage) async {
        guard message.sendFailed, let data = message.voice?.data else { return }
        _ = await sendVoice(
            data: data,
            durationMs: message.voice?.durationMs ?? 0,
            replacingFailed: message.clientOperationID,
            replyTo: message.replyTo
        )
    }

    private func sendVoice(
        data: Data,
        durationMs: Int,
        replacingFailed failedOperationID: UUID?,
        replyTo: ThreadChatItemID?
    ) async -> Bool {
        guard let ownerUserID = participants.currentUserID, isChatAvailable else {
            notice = .unavailable
            return false
        }
        guard !isQueueing else { return false }
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
                        finalizeOperation: operationProvider.makeOperation()
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
}
