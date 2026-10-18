import Foundation

nonisolated struct DailyChallengeTodayRequest: Encodable {
    let dayKey: String

    enum CodingKeys: String, CodingKey {
        case dayKey = "p_day_key"
    }
}

nonisolated struct DailyChallengeClientOperationRequest: Encodable {
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(operation: SyncClientOperation) {
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated struct DailyAnswerDetailsRequest: Encodable {
    let coupleDayID: UUID

    enum CodingKeys: String, CodingKey {
        case coupleDayID = "p_couple_day_id"
    }
}

nonisolated struct SubmitDailyAnswerRequest: Encodable {
    let instanceID: UUID
    let payload: DailyAnswerPayloadBody
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(instanceID: UUID, answerID: UUID, payload: DailyAnswerPayload, operation: SyncClientOperation) {
        self.instanceID = instanceID
        self.payload = DailyAnswerPayloadBody(answerID: answerID, payload: payload)
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case instanceID = "p_instance_id"
        case payload = "p_payload"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

/// `topics:submit_topic_answer`: the daily answer request plus the question it answers.
nonisolated struct SubmitTopicAnswerRequest: Encodable {
    let questionID: UUID
    let instanceID: UUID
    let payload: DailyAnswerPayloadBody
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(
        questionID: UUID,
        instanceID: UUID,
        answerID: UUID,
        payload: DailyAnswerPayload,
        operation: SyncClientOperation
    ) {
        self.questionID = questionID
        self.instanceID = instanceID
        self.payload = DailyAnswerPayloadBody(answerID: answerID, payload: payload)
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case questionID = "p_question_id"
        case instanceID = "p_instance_id"
        case payload = "p_payload"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated struct SubmitTopicAnswerResult: Decodable {
    let answerID: UUID
    let instanceID: UUID

    enum CodingKeys: String, CodingKey {
        case answerID = "answer_id"
        case instanceID = "instance_id"
    }
}

/// Encodes the `p_payload` JSON the backend expects, carrying a client-generated
/// `answer_id` for idempotency plus the per-kind fields. Only text is sent today;
/// partner-choice and media fields are added with their features.
nonisolated struct DailyAnswerPayloadBody: Encodable {
    let answerID: UUID
    let payload: DailyAnswerPayload

    enum CodingKeys: String, CodingKey {
        case answerID = "answer_id"
        case text
        case partnerChoiceUserID = "partner_choice_user_id"
        case mediaAssetIDs = "media_asset_ids"
        case optionChoice = "option_choice"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(answerID, forKey: .answerID)
        // Any combination the backend allows: a text body, a partner pick, and/or
        // media ids — only the parts that are present are sent.
        if let text = payload.text {
            try container.encode(text, forKey: .text)
        }
        if let userID = payload.partnerChoiceUserID {
            try container.encode(userID, forKey: .partnerChoiceUserID)
        }
        if !payload.mediaAssetIDs.isEmpty {
            try container.encode(payload.mediaAssetIDs, forKey: .mediaAssetIDs)
        }
        if let option = payload.optionChoice {
            try container.encode(option, forKey: .optionChoice)
        }
    }
}

nonisolated struct EditDailyTextAnswerRequest: Encodable {
    let instanceID: UUID
    let text: String
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(instanceID: UUID, text: String, operation: SyncClientOperation) {
        self.instanceID = instanceID
        self.text = text
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case instanceID = "p_instance_id"
        case text = "p_text"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated struct EditDailyPartnerChoiceRequest: Encodable {
    let instanceID: UUID
    let selectedUserID: UUID
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(instanceID: UUID, selectedUserID: UUID, operation: SyncClientOperation) {
        self.instanceID = instanceID
        self.selectedUserID = selectedUserID
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case instanceID = "p_instance_id"
        case selectedUserID = "p_selected_user_id"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated struct ShuffleDailyQuestionRequest: Encodable {
    let slotNumber: Int
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(slotNumber: Int, operation: SyncClientOperation) {
        self.slotNumber = slotNumber
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case slotNumber = "p_slot_number"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}
