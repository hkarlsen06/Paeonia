import ExyteChat
import Foundation

/// Building the list: one section per day of the question, the messages between the days,
/// and the times ExyteChat groups and orders by.
extension ThreadChatProjection {
    /// A row ready to hand to ExyteChat, with the time it really happened.
    private struct PlacedRow {
        let row: ThreadChatRow
        let user: ExyteChat.User
        let redrawToken: UUID
        var text = ""
        var status: ExyteChat.Message.Status?
        /// The user's own reaction, so the long-press menu marks it.
        var reactions: [ExyteChat.Reaction] = []
    }

    /// What building one message row reads besides the message itself.
    private struct MessageRowContext {
        let input: Input
        let messagesByID: [UUID: ThreadChatMessage]
        let readReceiptMessageID: UUID?
        let lastSentOwnMessage: ThreadChatMessage?
        let typingJoinsPrevious: Bool
    }

    /// A millisecond keeps the parts of a day in order without passing a real message.
    private static let step: TimeInterval = 0.001

    static func make(input: Input) -> ThreadChatProjection {
        // The dots join the partner's newest message when it is the last one, like Tidex.
        let typingJoinsPrevious = input.partnerIsTyping && input.messages.last.map {
            $0.senderUserID != input.currentUserID && !$0.hasMedia && !$0.isDeleted
        } == true
        let lastSentOwnMessage = input.messages.last {
            $0.senderUserID == input.currentUserID && !$0.isSending && !$0.sendFailed && !$0.isDeleted
        }

        let sections = input.rounds.map {
            roundSection($0, input: input, lastSentOwnMessage: lastSentOwnMessage)
        }
        let messages = messageRows(
            input: input,
            lastSentOwnMessage: lastSentOwnMessage,
            typingJoinsPrevious: typingJoinsPrevious
        )
        var placed = arranged(sections: sections, messages: messages)
        if let header = input.header {
            placed.insert(contentsOf: subjectRows(header, before: placed, input: input), at: 0)
        }
        if input.partnerIsTyping {
            placed.append(typingRow(after: placed, joinsPrevious: typingJoinsPrevious, input: input))
        }
        return projection(of: placed)
    }

    private static func chatUser(_ userID: UUID?, isCurrentUser: Bool, input: Input) -> ExyteChat.User {
        ExyteChat.User(
            id: userID?.uuidString ?? "question",
            name: isCurrentUser ? input.youName : input.partnerName,
            avatarURL: nil,
            isCurrentUser: isCurrentUser
        )
    }

    private static func placedRow(
        _ row: ThreadChatRow,
        user: ExyteChat.User,
        redrawKey: some Hashable,
        text: String = "",
        status: ExyteChat.Message.Status? = nil
    ) -> PlacedRow {
        PlacedRow(row: row, user: user, redrawToken: redrawToken(of: redrawKey), text: text, status: status)
    }

    // MARK: - One day

    /// One day of the question: Paeonia's question, an optional partner-choice match line,
    /// the answers, and a note on what the day waits for. The rows stay together.
    private static func roundSection(
        _ round: DailyChatRound,
        input: Input,
        lastSentOwnMessage: ThreadChatMessage?
    ) -> [PlacedRow] {
        let nobody = chatUser(nil, isCurrentUser: false, input: input)
        let questionAt = round.answers.first.map { $0.answeredAt.addingTimeInterval(-2 * step) } ?? round.startsAt
        var rows = [placedRow(
            decoration(questionRowID(for: round.instanceID), .question(round.prompt), at: questionAt),
            user: nobody,
            redrawKey: round.prompt,
            text: round.prompt
        )]

        if let match = round.match, let firstAnswer = round.answers.first {
            let row = decoration(
                matchRowPrefix + round.instanceID.uuidString,
                .partnerChoiceMatch(match, celebrationID: round.celebratesMatch ? round.instanceID : nil),
                at: firstAnswer.answeredAt.addingTimeInterval(-step)
            )
            let key = MatchRedrawKey(match: match, celebrates: round.celebratesMatch, partnerName: input.partnerName)
            rows.append(placedRow(row, user: nobody, redrawKey: key))
        }

        for answer in round.answers {
            rows.append(answerRow(answer, in: round, lastSentOwnMessage: lastSentOwnMessage, input: input))
        }

        if let waiting = round.waiting {
            let at = (round.answers.last?.answeredAt ?? round.startsAt).addingTimeInterval(step)
            let key = WaitingRedrawKey(waiting: waiting, partnerName: input.partnerName)
            rows.append(placedRow(
                decoration(waitingRowPrefix + round.instanceID.uuidString, .waiting(waiting), at: at),
                user: nobody,
                redrawKey: key
            ))
        }
        return rows
    }

    private static func decoration(_ id: String, _ kind: ThreadChatRow.Kind, at createdAt: Date) -> ThreadChatRow {
        ThreadChatRow(
            id: id,
            kind: kind,
            isCurrentUser: false,
            createdAt: createdAt,
            groupContext: .standalone(isCurrentUser: false),
            status: nil,
            quotedPreview: nil
        )
    }

    private static func answerRow(
        _ answer: DailyQuestionAnswerDetail,
        in round: DailyChatRound,
        lastSentOwnMessage: ThreadChatMessage?,
        input: Input
    ) -> PlacedRow {
        // Read shows on your answer until you send a message after it, which then carries it.
        let carriedByMessage = lastSentOwnMessage.map { $0.createdAt > answer.answeredAt } ?? false
        let status: ThreadChatMessageStatus? =
            answer.isOwnAnswer && round.ownAnswerSeenByPartner && !carriedByMessage ? .read : nil
        let reactions = sortedReactions(on: .answer(answer.answerID), input: input)
        let row = ThreadChatRow(
            id: answerRowID(for: answer.answerID),
            kind: .answer(answer, mediaKind: round.mediaKind),
            isCurrentUser: answer.isOwnAnswer,
            createdAt: answer.answeredAt,
            groupContext: .standalone(isCurrentUser: answer.isOwnAnswer),
            status: status,
            quotedPreview: nil,
            reactions: reactions
        )
        var placed = placedRow(
            row,
            user: chatUser(answer.answerUserID, isCurrentUser: answer.isOwnAnswer, input: input),
            redrawKey: AnswerRedrawKey(
                answer: answer,
                status: status,
                mediaKind: round.mediaKind,
                reactions: reactions
            ),
            text: answer.textBody ?? ""
        )
        placed.reactions = ownExyteReaction(in: reactions, input: input)
        return placed
    }

    /// The reactions on an item, in the same order every time.
    private static func sortedReactions(on item: ThreadChatItemID, input: Input) -> [EmojiReaction] {
        (input.reactions[item] ?? []).sorted { $0.userID.uuidString < $1.userID.uuidString }
    }

    /// The user's own reaction in ExyteChat's form, so its long-press menu marks it.
    private static func ownExyteReaction(in reactions: [EmojiReaction], input: Input) -> [ExyteChat.Reaction] {
        let currentUser = chatUser(input.currentUserID, isCurrentUser: true, input: input)
        return reactions.filter { $0.userID == input.currentUserID }.map {
            ExyteChat.Reaction(id: $0.userID.uuidString, user: currentUser, type: .emoji($0.emoji), status: .sent)
        }
    }

    // MARK: - Messages

    private static func messageRows(
        input: Input,
        lastSentOwnMessage: ThreadChatMessage?,
        typingJoinsPrevious: Bool
    ) -> [PlacedRow] {
        let messagesByID = Dictionary(input.messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let context = MessageRowContext(
            input: input,
            messagesByID: messagesByID,
            readReceiptMessageID: readReceiptMessageID(input: input, messagesByID: messagesByID),
            lastSentOwnMessage: lastSentOwnMessage,
            typingJoinsPrevious: typingJoinsPrevious
        )
        return input.messages.enumerated().map { messageRow($1, at: $0, context: context) }
    }

    private static func messageRow(
        _ message: ThreadChatMessage,
        at index: Int,
        context: MessageRowContext
    ) -> PlacedRow {
        let input = context.input
        let isCurrentUser = message.senderUserID == input.currentUserID
        let groupContext = runContext(of: message, at: index, context: context)
        let status = messageStatus(message, context: context)
        let quotedPreview = message.replyTo.map { target in
            preview(of: target, messages: context.messagesByID, input: input)
        }
        let reactions = sortedReactions(on: .message(message.id), input: input)
        let row = ThreadChatRow(
            id: rowID(for: message),
            kind: .message(message),
            isCurrentUser: isCurrentUser,
            createdAt: message.createdAt,
            groupContext: groupContext,
            status: status,
            quotedPreview: quotedPreview,
            reactions: reactions
        )
        var placed = placedRow(
            row,
            user: chatUser(message.senderUserID, isCurrentUser: isCurrentUser, input: input),
            redrawKey: MessageRedrawKey(
                message: message,
                groupContext: groupContext,
                status: status,
                quotedPreview: quotedPreview,
                reactions: reactions
            ),
            text: message.voice == nil ? message.body : "",
            status: message.isSending || message.sendFailed ? .sending : .sent
        )
        placed.reactions = ownExyteReaction(in: reactions, input: input)
        return placed
    }

    /// Where the message sits in its run. The typing dots continue the newest message's run.
    private static func runContext(
        of message: ThreadChatMessage,
        at index: Int,
        context: MessageRowContext
    ) -> ThreadChatGroupContext {
        let messages = context.input.messages
        let groupContext = ThreadChatGrouping.context(
            for: message,
            previous: index > 0 ? messages[index - 1] : nil,
            next: index + 1 < messages.count ? messages[index + 1] : nil,
            currentUserID: context.input.currentUserID
        )
        guard context.typingJoinsPrevious, index == messages.count - 1 else { return groupContext }
        return groupContext.joiningNext()
    }

    private static func messageStatus(
        _ message: ThreadChatMessage,
        context: MessageRowContext
    ) -> ThreadChatMessageStatus? {
        if message.sendFailed {
            .failed
        } else if message.isSending {
            .sending
        } else if message.id == context.readReceiptMessageID {
            .read
        } else if message.id == context.lastSentOwnMessage?.id {
            .sent
        } else {
            nil
        }
    }

    /// The card that opens a memory's or a story's chat, then a memory's notes, each from the
    /// person who wrote it. They are dated just before the first row, so they stay on top and
    /// in that row's day.
    private static func subjectRows(_ header: ThreadChatHeader, before rows: [PlacedRow], input: Input) -> [PlacedRow] {
        let firstAt = rows.map(\.row.createdAt).min() ?? .now
        let headerAt = firstAt.addingTimeInterval(-Double(header.notes.count + 1) * step)
        let card = placedRow(
            decoration(headerRowID, .subjectHeader(header), at: headerAt),
            user: chatUser(nil, isCurrentUser: false, input: input),
            redrawKey: header
        )
        let notes = header.notes.enumerated().map { index, note in
            let row = ThreadChatRow(
                id: noteRowPrefix + (note.isOwn ? "own" : "partner"),
                kind: .note(note),
                isCurrentUser: note.isOwn,
                createdAt: headerAt.addingTimeInterval(Double(index + 1) * step),
                groupContext: .standalone(isCurrentUser: note.isOwn),
                status: nil,
                quotedPreview: nil
            )
            return placedRow(
                row,
                user: chatUser(note.isOwn ? input.currentUserID : nil, isCurrentUser: note.isOwn, input: input),
                redrawKey: NoteRedrawKey(note: note, partnerName: input.partnerName),
                text: note.body
            )
        }
        return [card] + notes
    }

    private static func typingRow(after rows: [PlacedRow], joinsPrevious: Bool, input: Input) -> PlacedRow {
        // Dated like the newest row, so the dots stay in its day and at the bottom.
        let row = ThreadChatRow(
            id: typingRowID,
            kind: .typing,
            isCurrentUser: false,
            createdAt: rows.map(\.row.createdAt).max() ?? .now,
            groupContext: ThreadChatGroupContext(
                position: joinsPrevious ? .trailing : .standalone,
                isCurrentUser: false
            ),
            status: nil,
            quotedPreview: nil
        )
        return placedRow(row, user: chatUser(nil, isCurrentUser: false, input: input), redrawKey: joinsPrevious)
    }

    // MARK: - Order and time

    /// Each day stays whole, days follow one another, and a message goes after the last day
    /// that began before it was sent. A late answer to an old day therefore stays with that
    /// day instead of moving under a newer one.
    private static func arranged(sections: [[PlacedRow]], messages: [PlacedRow]) -> [PlacedRow] {
        let anchors = sections.map { $0.first?.row.createdAt ?? .distantFuture }
        var messagesAfter = [Int: [PlacedRow]]()
        for message in messages {
            let section = anchors.lastIndex { $0 <= message.row.createdAt } ?? -1
            messagesAfter[section, default: []].append(message)
        }
        var result = messagesAfter[-1] ?? []
        for (index, section) in sections.enumerated() {
            result += section + (messagesAfter[index] ?? [])
        }
        return result
    }

    /// ExyteChat puts each row in the day of its time and keeps the order it is given
    /// inside a day. So a row's time must never go back, and a late answer takes the time
    /// of the row before it when it came after the next day began. The rows keep their real
    /// times for display.
    private static func projection(of placed: [PlacedRow]) -> ThreadChatProjection {
        var nextQuestionAt: [Date?] = Array(repeating: nil, count: placed.count)
        var upcoming: Date?
        for index in placed.indices.reversed() {
            nextQuestionAt[index] = upcoming
            if case .question = placed[index].row.kind { upcoming = placed[index].row.createdAt }
        }

        var exyteMessages: [ExyteChat.Message] = []
        var rowsByID: [String: ThreadChatRow] = [:]
        exyteMessages.reserveCapacity(placed.count)
        rowsByID.reserveCapacity(placed.count)
        var previous = Date.distantPast
        for (index, item) in placed.enumerated() {
            var time = item.row.createdAt
            if let limit = nextQuestionAt[index], time > limit { time = previous }
            time = max(time, previous)
            previous = time
            var message = ExyteChat.Message(
                id: item.row.id,
                user: item.user,
                status: item.status,
                createdAt: time,
                text: item.text,
                reactions: item.reactions
            )
            message.triggerRedraw = item.redrawToken
            exyteMessages.append(message)
            rowsByID[item.row.id] = item.row
        }
        return ThreadChatProjection(exyteMessages: exyteMessages, rowsByID: rowsByID)
    }

    /// Your newest message the partner has read through. The partner's mark is a
    /// message id, so read means sent at or before that message.
    private static func readReceiptMessageID(
        input: Input,
        messagesByID: [UUID: ThreadChatMessage]
    ) -> UUID? {
        guard let readID = input.partnerLastReadMessageID, let readThrough = messagesByID[readID] else { return nil }
        return input.messages.last { message in
            message.senderUserID == input.currentUserID
                && !message.isSending
                && !message.sendFailed
                && !message.isDeleted
                && (message.createdAt, message.id.uuidString) <= (readThrough.createdAt, readThrough.id.uuidString)
        }?.id
    }

    /// Everything a message row draws that ExyteChat's message doesn't carry. ExyteChat
    /// only redraws a row whose message changed, so this goes into `triggerRedraw`.
    private struct AnswerRedrawKey: Hashable {
        let answer: DailyQuestionAnswerDetail
        let status: ThreadChatMessageStatus?
        let mediaKind: DailyChallengeAnswerKind
        let reactions: [EmojiReaction]
    }

    private struct MatchRedrawKey: Hashable {
        let match: PartnerChoiceMatch
        let celebrates: Bool
        let partnerName: String
    }

    private struct NoteRedrawKey: Hashable {
        let note: ThreadChatNote
        let partnerName: String
    }

    private struct WaitingRedrawKey: Hashable {
        let waiting: DailyChatRound.Waiting
        let partnerName: String
    }

    private struct MessageRedrawKey: Hashable {
        let body: String
        let isSending: Bool
        let sendFailed: Bool
        let voiceAssetID: UUID?
        let hasLocalVoice: Bool
        let photoAssetIDs: [UUID?]
        let hasLocalPhotos: Bool
        let isEdited: Bool
        let isDeleted: Bool
        let groupContext: ThreadChatGroupContext
        let status: ThreadChatMessageStatus?
        let quotedPreview: ThreadChatReplyPreview?
        let reactions: [EmojiReaction]

        init(
            message: ThreadChatMessage,
            groupContext: ThreadChatGroupContext,
            status: ThreadChatMessageStatus?,
            quotedPreview: ThreadChatReplyPreview?,
            reactions: [EmojiReaction]
        ) {
            body = message.body
            isSending = message.isSending
            sendFailed = message.sendFailed
            voiceAssetID = message.voice?.mediaAssetID
            hasLocalVoice = message.voice?.data != nil
            photoAssetIDs = (message.photos ?? []).map(\.mediaAssetID)
            hasLocalPhotos = (message.photos ?? []).contains { $0.data != nil }
            isEdited = message.editedAt != nil
            isDeleted = message.isDeleted
            self.groupContext = groupContext
            self.status = status
            self.quotedPreview = quotedPreview
            self.reactions = reactions
        }
    }
}
