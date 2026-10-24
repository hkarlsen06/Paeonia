import Foundation

extension DailyChallengeViewModel {
    /// Builds the view model for the earlier days on the Questions tab, sharing this
    /// screen's service and current identity.
    func makeHistoryViewModel() -> DailyChallengeHistoryViewModel {
        DailyChallengeHistoryViewModel(service: service, currentUserID: currentUserID)
    }

    /// Reads a question's chat before its screen opens, so the screen's first frame
    /// is complete. Callers await this, then open the screen. The page scrolls to
    /// `question`'s day, or to the question's newest day when `focusesNewest` is set.
    /// A partner answer the user hasn't seen yet plays its reveal.
    func prepareChat(for question: DailyChallengeQuestion, focusesNewest: Bool = false) async {
        let chat = newChatViewModel(question: question, focusesNewest: focusesNewest)
        chat.revealsPartnerAnswer = hasNewPartnerAnswer(question)
        await chat.prepare()
        preparedChat = chat
    }

    /// The chat prepared for `question`, with the focus it was prepared with.
    func makeChatViewModel(question: DailyChallengeQuestion) -> ThreadChatViewModel {
        if let preparedChat, preparedChat.question?.id == question.id {
            return preparedChat
        }
        return newChatViewModel(question: question, focusesNewest: false)
    }

    private func newChatViewModel(question: DailyChallengeQuestion, focusesNewest: Bool) -> ThreadChatViewModel {
        ThreadChatViewModel(
            question: question,
            participants: participants,
            focusesNewest: focusesNewest,
            service: chatService,
            operationProvider: operationProvider,
            // The thread summaries live feed keeps previews current. A one-shot
            // summaries read here could replace them with an older list.
            syncAfterLocalChange: { [weak self] in
                await self?.localChangeSyncHandler?()
            }
        )
    }

    /// A couple has one chat per question, so every day of a question shares its preview.
    func threadPreview(for questionID: UUID) -> String? {
        threadSummariesByQuestionID[questionID]?.lastMessagePreview
    }

    func hasUnreadChat(for questionID: UUID) -> Bool {
        guard let summary = threadSummariesByQuestionID[questionID], let currentUserID else { return false }
        return summary.isUnread(by: currentUserID, readThrough: chatReadMarks[summary.threadID])
    }

    /// The user can read the partner's answer and hasn't seen it yet.
    func hasNewPartnerAnswer(_ question: DailyChallengeQuestion) -> Bool {
        question.hasNewPartnerAnswer(seen: seenPartnerAnswerIDs)
    }

    /// Sends answers seen on this phone that the server doesn't know about yet. Runs
    /// whenever the questions or the seen list change, so one that failed offline is
    /// sent again once a live update arrives. The server keeps the first time it heard.
    func uploadSeenPartnerAnswers() {
        let pending = (snapshot.questions + topicQuestions.values).filter {
            seenPartnerAnswerIDs.contains($0.id) && $0.hasRevealedPartnerAnswer && $0.partnerAnswerSeenAt == nil
                && !seenAnswerUploads.contains($0.id)
        }
        for question in pending {
            seenAnswerUploads.insert(question.id)
            let chatService = chatService
            Task { @MainActor [weak self] in
                await chatService.markPartnerAnswerSeenOnServer(instanceID: question.id)
                self?.seenAnswerUploads.remove(question.id)
            }
        }
    }

    /// Something from the partner the user hasn't seen yet: a new answer or a chat message.
    func hasNewFromPartner(_ question: DailyChallengeQuestion) -> Bool {
        hasNewPartnerAnswer(question) || (question.isChatAvailable && hasUnreadChat(for: question.questionID))
    }

    /// Chats with a partner message the user has not opened yet, newest first.
    var unreadChats: [ThreadChatSummary] {
        guard let currentUserID else { return [] }
        return threadSummariesByQuestionID.values
            .filter { $0.isUnread(by: currentUserID, readThrough: chatReadMarks[$0.threadID]) }
            .sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
    }

    /// The question text for a chat, when today's questions include it.
    func questionPrompt(for questionID: UUID) -> String? {
        snapshot.questions.first(where: { $0.questionID == questionID })?.prompt
    }

    /// Chats with a partner message the user has not opened yet, from daily questions
    /// only. Home and other shared screens list these. Topic chats show on the Topics card.
    var unreadDailyChats: [ThreadChatSummary] {
        unreadChats.filter { $0.topicKey == nil }
    }

    /// Today's copy of a question opened earlier, so an open page sees the partner's
    /// answer arrive. Older questions are not in today's snapshot and stay as they were.
    func latestQuestion(_ question: DailyChallengeQuestion) -> DailyChallengeQuestion {
        knownQuestion(question.id) ?? question
    }

    /// The question's newest day the user can open a chat from, to open the question's
    /// chat when only the question is known: from a message, a notification, or the Home
    /// card. Today's questions come first, then the question history.
    func questionForChat(questionID: UUID) async -> DailyChallengeQuestion? {
        func newest(in questions: [DailyChallengeQuestion]) -> DailyChallengeQuestion? {
            questions
                .filter { $0.questionID == questionID && $0.isChatAvailable }
                .max { ($0.startsAt, $0.id.uuidString) < ($1.startsAt, $1.id.uuidString) }
        }
        if let question = newest(in: snapshot.questions) { return question }
        guard let currentUserID else { return nil }
        guard let questions = try? await service.loadHistory(currentUserID: currentUserID) else {
            return nil
        }
        return newest(in: questions)
    }

    /// The day with this instance id, to open the question's chat on that day. History
    /// rows cover days the user answered earlier than today.
    func questionForChat(instanceID: UUID) async -> DailyChallengeQuestion? {
        if let question = knownQuestion(instanceID), question.isChatAvailable {
            return question
        }
        guard let currentUserID else { return nil }
        guard let questions = try? await service.loadHistory(currentUserID: currentUserID) else {
            return nil
        }
        return questions.first(where: { $0.id == instanceID && $0.isChatAvailable })
    }
}
