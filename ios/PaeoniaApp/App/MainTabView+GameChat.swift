import SwiftUI

struct GameChatDestination: Hashable, Identifiable {
    let subject: GameChatSubject
    let viewModel: ThreadChatViewModel

    var id: UUID { subject.id }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension MainTabView {
    func resetGameChatNavigation() {
        gameChatReturn.isPending = false
        gameChatReturn.waitsForKeyboard = false
        gameChatReturn.layoutReadyFrame = nil
        messageNoticeStartedAt = Date()
        visibleChatSubject = nil
        gameChatDestination = nil
        gameChatSheet = nil
        openingGameChatID = nil
    }

    /// Shared chat dependencies and the root-owned game navigation actions.
    var threadChatContext: ThreadChatContext {
        var context = ThreadChatContext(
            coupleID: identity.coupleID,
            participants: dailyChallengeParticipants,
            summaries: chatSummaries,
            memories: memoriesViewModel,
            gameDrawings: gamesViewModel.historyDrawings,
            service: dailyChallengeViewModel.chatService,
            operationProvider: dailyChallengeViewModel.operationProvider,
            syncAfterLocalChange: actions.syncAfterLocalChange,
            reporting: ChatReporting(
                service: dependencies.settingsPrivacyService,
                operationProvider: dependencies.settingsPrivacyOperationProvider,
                onReportedAndLeft: actions.leftRelationship
            )
        )
        context.gamePreview = { kind in await gamesViewModel.chatPreview(for: kind) }
        context.openGameChat = { kind, source, result in
            openGameChat(kind: kind, source: source, result: result)
        }
        context.chatVisibilityChanged = { subject, isVisible in
            if isVisible {
                visibleChatSubject = subject
            } else if visibleChatSubject == subject {
                visibleChatSubject = nil
            }
        }
        context.preservesGamePresentation = { kind in
            selection.wrappedValue == .questions && gamesPath.contains(.game(kind))
        }
        return context
    }

    var retainedGameKinds: Set<GameKind> {
        guard selection.wrappedValue == .questions else { return [] }
        return Set(gamesPath.compactMap { destination in
            if case let .game(kind) = destination { return kind }
            return nil
        })
    }

    /// Opens a game's chat. With a game screen open in Games, the chat opens as a sheet over
    /// it, so the game stays on screen. Anywhere else it opens in Chats.
    func openGameChat(
        kind: GameKind, source: GameConversationSource? = nil, result: GameConversationResult? = nil
    ) {
        guard let coupleID = identity.coupleID else { return }
        let subject = GameChatSubject(coupleID: coupleID, kind: kind)
        let opensOverGame = selection.wrappedValue == .games && !gamesPath.isEmpty
        let existing = (opensOverGame ? gameChatSheet : gameChatDestination)
            .flatMap { $0.subject == subject ? $0 : nil }
        if opensOverGame {
            PaeoniaKeyboard.dismiss()
        } else {
            selectTab(.questions)
            dailyChatQuestion = nil
            requestedConversationID = nil
            if existing == nil { questionsPath = [] }
        }
        let requestID = UUID()
        openingGameChatID = requestID
        Task { @MainActor in
            let model: ThreadChatViewModel?
            if let destination = existing {
                model = destination.viewModel
            } else {
                model = await threadChatContext.makeViewModel(subject: .game(subject), header: .game(subject))
            }
            guard openingGameChatID == requestID, identity.coupleID == coupleID, let model else { return }
            if let source { await model.focusGameResult(source: source, result: result) }
            guard openingGameChatID == requestID, identity.coupleID == coupleID else { return }
            let destination = GameChatDestination(subject: subject, viewModel: model)
            if opensOverGame { gameChatSheet = destination } else { gameChatDestination = destination }
            openingGameChatID = nil
        }
    }

    /// Opens the couple chat in Chats, over whatever that tab had pushed.
    func openCoupleChat() {
        selectTab(.questions)
        dailyChatQuestion = nil
        gameChatDestination = nil
        questionsPath = []
        isCoupleChatRequested = true
    }

    /// The live summary feed supplies authorized previews even when APNs is unavailable.
    func announcePartnerMessage(
        previous: [ThreadChatSubject: ThreadChatSummary], current: [ThreadChatSubject: ThreadChatSummary]
    ) {
        guard scenePhase == .active, let partnerID = identity.partnerUserID else { return }
        let arrivals = current.values.filter { summary in
            guard let messageID = summary.lastMessageID, let date = summary.lastMessageAt else { return false }
            return summary.lastMessageSenderUserID == partnerID
                && previous[summary.subject]?.lastMessageID != messageID
                && date >= messageNoticeStartedAt
                && summary.isPrivateTopic != true
                && visibleChatSubject != summary.subject
        }.sorted { ($0.lastMessageAt ?? .distantPast) < ($1.lastMessageAt ?? .distantPast) }
        for summary in arrivals {
            guard let preview = summary.lastMessagePreview else { continue }
            var title = reactionPartnerName
            var gameKind: GameKind?
            if case .game(let game) = summary.subject {
                gameKind = game.kind
                title = String(
                    localized: .gamesChatMessageTitle(reactionPartnerName, String(localized: game.kind.name))
                )
            }
            bannerCenter.show(
                .info(
                    title: title, message: preview, gameKind: gameKind,
                    imageData: PaeoniaAppGroup.partnerAvatarData(),
                    systemImage: "bubble.left.and.bubble.right.fill", action: openChatAction(for: summary.subject)
                )
            )
        }
    }

    /// What tapping a partner message's banner opens: the chat it arrived in.
    private func openChatAction(for subject: ThreadChatSubject) -> () -> Void {
        switch subject {
        case .game(let game): { openGameChat(kind: game.kind) }
        case .question(let id): { PaeoniaNotificationRouter.shared.route(.dailyChat(questionID: id)) }
        case .memory(let id): { PaeoniaNotificationRouter.shared.route(.memory(memoryID: id, showsComments: true)) }
        case .story(let id): { PaeoniaNotificationRouter.shared.route(.story(storyID: id, showsReplies: true)) }
        case .couple: { openCoupleChat() }
        }
    }
}
