import Foundation

nonisolated struct MediaAlternativeAcceptedText: Decodable, Sendable {
    let accessibilityText: String?
    var widgetRevisionVersion: Int64?
    enum CodingKeys: String, CodingKey {
        case accessibilityText = "accessibility_text"
        case widgetRevisionVersion = "revision_description_version"
    }
}

nonisolated protocol MediaAlternativeGateway: Sendable {
    func update(_ edit: MediaAlternativeEdit, operation: SyncClientOperation) async throws
        -> MediaAlternativeAcceptedText
}

nonisolated struct LiveMediaAlternativeGateway: MediaAlternativeGateway {
    let client: PaeoniaConvexClient

    func update(_ edit: MediaAlternativeEdit, operation: SyncClientOperation) async throws
        -> MediaAlternativeAcceptedText {
        let result: MediaAlternativeAcceptedText = try await client.mutation(
            "media:update_accessibility_text",
            args: Request(edit: edit, operation: GameClientOperationFields(operation))
        )
        return result
    }

    private struct Request: Encodable {
        let edit: MediaAlternativeEdit
        let operation: GameClientOperationFields
        enum CodingKeys: String, CodingKey { case target = "p_target", text = "p_text" }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Target(edit.target), forKey: .target)
            try container.encode(edit.text, forKey: .text)
            try operation.encode(to: encoder)
        }
    }

    private struct Target: Encodable {
        let value: MediaAlternativeTarget
        init(_ value: MediaAlternativeTarget) { self.value = value }
        enum CodingKeys: String, CodingKey {
            case kind, messageID = "message_id", assetID = "media_asset_id"
            case answerID = "answer_id", storyID = "story_id", roundID = "round_id"
            case partID = "part_id", revisionID = "revision_id"
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch value {
            case let .chat(messageID, mediaAssetID):
                try container.encode("chat", forKey: .kind)
                try container.encode(messageID, forKey: .messageID)
                try container.encode(mediaAssetID, forKey: .assetID)
            case let .daily(answerID):
                try container.encode("daily", forKey: .kind)
                try container.encode(answerID, forKey: .answerID)
            case let .story(storyID):
                try container.encode("story", forKey: .kind)
                try container.encode(storyID, forKey: .storyID)
            case let .guessMySpot(roundID):
                try container.encode("guess_my_spot", forKey: .kind)
                try container.encode(roundID, forKey: .roundID)
            case let .drawAndGuess(roundID):
                try container.encode("draw_and_guess", forKey: .kind)
                try container.encode(roundID, forKey: .roundID)
            case let .widgetDrawing(revisionID):
                try container.encode("widget_drawing", forKey: .kind)
                try container.encode(revisionID, forKey: .revisionID)
            case let .exquisiteCorpse(partID):
                try container.encode("exquisite_corpse", forKey: .kind)
                try container.encode(partID, forKey: .partID)
            }
        }
    }
}

struct MediaAlternativePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .updateMediaAlternative
    let gateway: any MediaAlternativeGateway
    let cache: MediaAlternativeCacheUpdater

    func send(_ operation: PendingSyncOperationSnapshot, context: SyncContext) async throws
        -> PendingSyncOperationSendResult {
        guard let data = operation.requestData else { throw PendingSyncOperationPayloadError() }
        let edit = try JSONDecoder().decodeQueuedPayload(MediaAlternativeEdit.self, from: data)
        if let coupleID = context.session.activeCoupleID, edit.coupleID != coupleID {
            return .terminalFailure("The description belongs to an earlier relationship")
        }
        let stamp = await cache.stamp(ownerUserID: operation.ownerUserID)
        let accepted = try await gateway.update(edit, operation: operation.operation)
        if case .widgetDrawing = edit.target, accepted.widgetRevisionVersion == nil {
            throw PendingSyncOperationPayloadError()
        }
        let service = MediaAlternativeEditingService(pending: context.pendingOperationStore, cache: cache)
        let latest = try await service.pendingEdit(
            ownerUserID: operation.ownerUserID, coupleID: edit.coupleID, target: edit.target
        )
        if latest?.operationID == operation.operation.id {
            let normalized = MediaAlternativeEdit(coupleID: edit.coupleID, target: edit.target,
                                                  text: accepted.accessibilityText ?? "")
            await cache.apply(normalized, ownerUserID: operation.ownerUserID, operation: operation.operation,
                              stamp: stamp, widgetRevisionVersion: accepted.widgetRevisionVersion)
        }
        return .succeeded
    }
}
