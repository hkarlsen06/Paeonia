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
        pendingGameChatSheet = nil
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
                bannerCenter.dismiss(announcing: subject)
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

    /// Opens a game's chat over the game, switching to Games and opening the game first
    /// when another screen is in front. A game that can't open yet, because Games has not
    /// loaded or the first-time steps come first, has its chat open in Chats instead.
    func openGameChat(
        kind: GameKind, source: GameConversationSource? = nil, result: GameConversationResult? = nil
    ) {
        guard let coupleID = identity.coupleID else { return }
        isCoupleChatSlidOver = false
        let subject = GameChatSubject(coupleID: coupleID, kind: kind)
        let requestID = UUID()
        openingGameChatID = requestID
        pendingGameChatSheet = nil
        PaeoniaKeyboard.dismiss()
        Task { @MainActor in
            defer { if openingGameChatID == requestID { openingGameChatID = nil } }
            let opensOverGame = await showGame(kind, for: requestID)
            guard openingGameChatID == requestID, identity.coupleID == coupleID else { return }
            let existing = (opensOverGame ? gameChatSheet : gameChatDestination)
                .flatMap { $0.subject == subject ? $0 : nil }
            if !opensOverGame { showChats(keepingPath: existing != nil) }
            let model: ThreadChatViewModel?
            if let destination = existing {
                model = destination.viewModel
            } else {
                model = await threadChatContext.makeViewModel(subject: .game(subject), header: .game(subject))
            }
            guard openingGameChatID == requestID, identity.coupleID == coupleID, let model else { return }
            if let source { await model.focusGameResult(source: source, result: result) }
            guard openingGameChatID == requestID, identity.coupleID == coupleID else { return }
            show(GameChatDestination(subject: subject, viewModel: model), overGame: opensOverGame)
        }
    }

    private func showChats(keepingPath: Bool) {
        selectTab(.questions)
        dailyChatQuestion = nil
        requestedConversationID = nil
        if !keepingPath { questionsPath = [] }
    }

    /// Over the game, or in Chats. A switch to Games that still waits opens it when it ends.
    private func show(_ destination: GameChatDestination, overGame: Bool) {
        if !overGame {
            gameChatDestination = destination
        } else if selection.wrappedValue == .games {
            gameChatSheet = destination
        } else {
            pendingGameChatSheet = destination
        }
    }

    /// A game's chat is open over the Games tab, or on its way there.
    var gameChatIsOpen: Bool {
        openingGameChatID != nil || pendingGameChatSheet != nil || gameChatSheet != nil
    }

    func gameChatTabChanged(to tab: MainTab) {
        if tab != .games {
            // The game under the sheet is no longer on screen.
            gameChatSheet = nil
            pendingGameChatSheet = nil
        } else if let pending = pendingGameChatSheet {
            pendingGameChatSheet = nil
            // A turn later, once the game is laid out on screen, so the panel measures it.
            Task { @MainActor in
                if selection.wrappedValue == .games { gameChatSheet = pending }
            }
        }
    }

    /// Brings a screen of the game to the front of Games and selects the tab. A screen of the
    /// game already open there stays. False when the game can't open yet.
    private func showGame(_ kind: GameKind, for requestID: UUID) async -> Bool {
        if gamesPath.last?.gameKind != kind {
            if !gamesViewModel.opensDirectly(kind) {
                // From this phone only, so a chat that has to open in Chats does not wait on the network.
                gamesViewModel.configure(participants: gamesParticipants)
                await gamesViewModel.reload()
                guard openingGameChatID == requestID, gamesViewModel.opensDirectly(kind) else { return false }
            }
            gameChatSheet = nil
            // At once, so the screen it replaces is gone before the new one shrinks under the
            // panel. Both share the stack the shrink draws smaller.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { gamesPath = [.game(kind)] }
        }
        if selection.wrappedValue != .games { selectTab(.games) }
        return true
    }

    /// Opens the couple chat in Chats, over whatever that tab had pushed. Already open over
    /// the tabs, it stays there.
    func openCoupleChat() {
        guard !isCoupleChatSlidOver else { return }
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
            var banner = PaeoniaBannerContent.info(
                title: title, message: preview, gameKind: gameKind,
                imageData: PaeoniaAppGroup.partnerAvatarData(),
                systemImage: "bubble.left.and.bubble.right.fill", action: openChatAction(for: summary.subject)
            )
            banner.chat = summary.subject
            bannerCenter.show(banner)
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
