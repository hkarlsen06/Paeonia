import Foundation

/// One photo, GIF or video in a chat message. A message keeps them in the order the
/// sender picked them, and the text, if any, is their caption.
nonisolated struct ThreadChatAttachment: Codable, Equatable, Hashable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case photo
        /// An animated GIF, sent byte for byte so it still moves.
        case gif
        case video

        /// The `media_type` the server stores. A GIF is an image there.
        var serverMediaType: String {
            self == .video ? "video" : "image"
        }
    }

    /// What this phone keeps of an attachment while it sends, or after it failed.
    nonisolated enum LocalCopy: Codable, Equatable, Hashable, Sendable {
        /// A compressed photo, at most about 1.5 MB.
        case bytes(Data)
        /// A GIF as picked or a prepared video, in `ThreadChatMediaFiles.directory`. Only the
        /// name is kept, because an app update moves the app's folders, and the bytes stay out
        /// of the queued send and the chat cache.
        case file(name: String)
    }

    let kind: Kind
    /// The uploaded file. Nil until the message is sent.
    var mediaAssetID: UUID?
    var local: LocalCopy?
    var width: Int?
    var height: Int?
    /// How long a video runs.
    var durationMs: Int?
    var accessibilityText: String?

    var localBytes: Data? {
        guard case let .bytes(data) = local else { return nil }
        return data
    }

    var localFileURL: URL? {
        guard case let .file(name) = local else { return nil }
        return ThreadChatMediaFiles.url(named: name)
    }

    /// What a chat preview calls a message that starts with this attachment.
    var previewLabel: LocalizedStringResource {
        switch kind {
        case .photo: .dailyChatPhotoPreview
        case .gif: .dailyChatGifPreview
        case .video: .mediaVideoLabel
        }
    }
}

/// The attachments of a queued message. Each one is reserved under the message's id,
/// and the upload operations are fixed so a retry reuses them. A GIF's or a video's bytes
/// stay in its file. Only its name travels in the queued operation.
nonisolated struct ThreadChatAttachmentsPayload: Codable, Equatable, Sendable {
    nonisolated struct Item: Codable, Equatable, Sendable {
        let kind: ThreadChatAttachment.Kind
        let local: ThreadChatAttachment.LocalCopy
        let width: Int
        let height: Int
        var durationMs: Int?
        let reserveOperation: SyncClientOperation
        let finalizeOperation: SyncClientOperation
        var accessibilityText: String?
    }

    let messageID: UUID
    let items: [Item]

    var pendingAttachments: [ThreadChatAttachment] {
        items.map { item in
            ThreadChatAttachment(
                kind: item.kind,
                local: item.local,
                width: item.width,
                height: item.height,
                durationMs: item.durationMs,
                accessibilityText: item.accessibilityText
            )
        }
    }
}

/// Where chat GIFs and videos wait from the moment they are picked until they are
/// uploaded. The privacy purge removes the whole outgoing folder. A file goes once its
/// upload is done, or when the person takes it out of the composer or deletes the unsent
/// message. `OutgoingMediaSweep` removes one that nothing names any more.
nonisolated enum ThreadChatMediaFiles {
    static var directory: URL {
        PreparedVideo.outgoingMediaDirectoryURL().appendingPathComponent("chat", isDirectory: true)
    }

    static func url(named name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    /// Keeps a picked GIF's bytes as a file, and returns its name.
    static func storeGIF(_ data: Data) throws -> String {
        try VideoPreparation.createOutgoingDirectory(directory)
        let name = "\(UUID().uuidString.lowercased()).gif"
        try data.write(to: url(named: name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return name
    }

    static func delete(_ attachments: [ThreadChatAttachment]) {
        for url in attachments.compactMap(\.localFileURL) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
