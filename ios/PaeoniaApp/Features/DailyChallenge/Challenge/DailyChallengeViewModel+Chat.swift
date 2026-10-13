import Foundation

extension DailyChallengeViewModel {
    /// Builds the view model for the earlier days on the Questions tab, sharing this
    /// screen's service and current identity.
    func makeHistoryViewModel() -> DailyChallengeHistoryViewModel {
        DailyChallengeHistoryViewModel(service: service, currentUserID: currentUserID)
    }

    /// Reads a question's chat before its screen opens, so the screen's first frame
    /// is complete. Callers await this, then open the screen.
    func prepareChat(for question: DailyChallengeQuestion) async {
        let chat = newChatViewModel(question: question)
        await chat.prepare()
        preparedChat = chat
    }

    func makeChatViewModel(question: DailyChallengeQuestion) -> DailyQuestionChatViewModel {
        if let preparedChat, preparedChat.question.id == question.id {
            return preparedChat
        }
        return newChatViewModel(question: question)
    }

    private func newChatViewModel(question: DailyChallengeQuestion) -> DailyQuestionChatViewModel {
        DailyQuestionChatViewModel(
            question: question,
            participants: participants,
            service: chatService,
            operationProvider: operationProvider,
            // The thread summaries live feed keeps previews current. A one-shot
            // summaries read here could replace them with an older list.
            syncAfterLocalChange: { [weak self] in
                await self?.localChangeSyncHandler?()
            }
        )
    }

    func threadPreview(for instanceID: UUID) -> String? {
        threadSummariesByInstanceID[instanceID]?.lastMessagePreview
    }

    func hasUnreadChat(for instanceID: UUID) -> Bool {
        guard let summary = threadSummariesByInstanceID[instanceID], let currentUserID else { return false }
        return summary.isUnread(by: currentUserID, readThrough: chatReadMarks[summary.threadID])
    }

    /// The user can read the partner's answer and hasn't seen it yet.
    func hasNewPartnerAnswer(_ question: DailyChallengeQuestion) -> Bool {
        question.hasNewPartnerAnswer(seen: seenPartnerAnswerIDs)
    }

    /// The answer flow showed the partner's answer. Saved on this phone first, which
    /// sends it to the server through `uploadSeenPartnerAnswers`.
    func markPartnerAnswerSeen(_ question: DailyChallengeQuestion) {
        Task { await DeliveredNotifications.clearQuestion(instanceID: question.id) }
        guard let currentUserID, question.isChatAvailable, question.partnerAnswerSeenAt == nil else { return }
        let chatService = chatService
        Task { await chatService.markPartnerAnswerSeen(ownerUserID: currentUserID, instanceID: question.id) }
    }

    /// Sends answers seen on this phone that the server doesn't know about yet. Runs
    /// whenever the questions or the seen list change, so one that failed offline is
    /// sent again once a live update arrives. The server keeps the first time it heard.
    func uploadSeenPartnerAnswers() {
        let pending = snapshot.questions.filter {
            seenPartnerAnswerIDs.contains($0.id) && $0.isChatAvailable && $0.partnerAnswerSeenAt == nil
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
        hasNewPartnerAnswer(question) || (question.isChatAvailable && hasUnreadChat(for: question.id))
    }

    /// Chats with a partner message the user has not opened yet, newest first.
    var unreadChats: [DailyQuestionThreadSummary] {
        guard let currentUserID else { return [] }
        return threadSummariesByInstanceID.values
            .filter { $0.isUnread(by: currentUserID, readThrough: chatReadMarks[$0.threadID]) }
            .sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
    }

    /// The question text for a chat, when today's questions include it.
    func questionPrompt(for instanceID: UUID) -> String? {
        snapshot.questions.first(where: { $0.id == instanceID })?.prompt
    }

    /// Today's copy of a question opened earlier, so an open page sees the partner's
    /// answer arrive. Older questions are not in today's snapshot and stay as they were.
    func latestQuestion(_ question: DailyChallengeQuestion) -> DailyChallengeQuestion {
        snapshot.questions.first(where: { $0.id == question.id }) ?? question
    }

    func refreshThreadSummaries() async {
        guard let currentUserID else { return }
        applyThreadSummaries(await chatService.cachedThreadSummaries(ownerUserID: currentUserID))
        if let summaries = try? await chatService.refreshThreadSummaries(ownerUserID: currentUserID) {
            applyThreadSummaries(summaries)
        }
    }

    func questionForChat(instanceID: UUID) async -> DailyChallengeQuestion? {
        if let question = snapshot.questions.first(where: { $0.id == instanceID && $0.isChatAvailable }) {
            return question
        }
        guard let currentUserID else { return nil }
        guard let questions = try? await service.loadHistory(currentUserID: currentUserID) else {
            return nil
        }
        return questions.first(where: { $0.id == instanceID && $0.isChatAvailable })
    }
}
