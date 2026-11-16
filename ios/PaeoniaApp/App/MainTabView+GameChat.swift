import SwiftUI

struct GameChatDestination: Hashable, Identifiable {
    let subject: GameChatSubject
    let viewModel: ThreadChatViewModel

    var id: UUID { subject.id }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A game's chat that a tap on another tab opened over its game, which switched to Games. Backing
/// out of it returns the person to that tab, and Games gets back the stack it had before. It is
/// dropped when anything else makes that way back wrong.
struct GameChatVisit {
    enum Stage {
        /// The chat is over the game. Closing it ends the visit.
        case chat
        /// The person tapped the game above the chat to stay in it. The game's Back ends the visit.
        case game
    }

    let kind: GameKind
    /// The tab the person came from.
    let origin: MainTab
    /// The Games stack before the visit.
    let originGamesPath: [GamesDestination]
    /// The Games stack the visit shows.
    let gamesPath: [GamesDestination]
    var stage = Stage.chat
}

extension MainTabView {
    func resetGameChatNavigation() {
        gameChatReturn.isPending = false
        gameChatReturn.waitsForKeyboard = false
        gameChatReturn.layoutReadyFrame = nil
        messageNoticeStartedAt = Date()
        visibleChatSubject = nil
        gameChatDestination = nil
        gameChatVisit = nil
        dismissGameChatSheet()
        openingGameChatID = nil
    }

    /// Closes a game's chat over the game, and one still on its way there.
    func dismissGameChatSheet() {
        gameChatSheet = nil
        pendingGameChatSheet = nil
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
    /// when another tab is in front, which starts a visit (`GameChatVisit`). A game that can't
    /// open yet, because Games has not loaded or the first-time steps come first, has its chat
    /// open in Chats instead.
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
            dismissGameChatSheet()
            gameChatVisit = nil
        } else if let pending = pendingGameChatSheet {
            pendingGameChatSheet = nil
            // A turn later, once the game is laid out on screen, so the panel measures it.
            Task { @MainActor in
                if selection.wrappedValue == .games, !isCoupleChatSlidOver { gameChatSheet = pending }
            }
        }
    }

    /// Brings a screen of the game to the front of Games and selects the tab, which starts a visit
    /// when another tab was in front. A screen of the game already open there stays. False when
    /// the game can't open yet.
    private func showGame(_ kind: GameKind, for requestID: UUID) async -> Bool {
        // Another game's chat ends a visit under way.
        if gameChatVisit?.kind != kind { gameChatVisit = nil }
        if gamesPath.last?.gameKind != kind, !gamesViewModel.opensDirectly(kind) {
            // From this phone only, so a chat that has to open in Chats does not wait on the network.
            gamesViewModel.configure(participants: gamesParticipants)
            await gamesViewModel.reload()
            guard openingGameChatID == requestID, gamesViewModel.opensDirectly(kind) else { return false }
        }
        let originGamesPath = gamesPath
        if gamesPath.last?.gameKind != kind {
            gameChatSheet = nil
            // At once, so the screen it replaces is gone before the new one shrinks under the
            // panel. Both share the stack the shrink draws smaller.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { gamesPath = [.game(kind)] }
        }
        let origin = selection.wrappedValue
        if origin != .games {
            selectTab(.games)
            gameChatVisit = GameChatVisit(
                kind: kind, origin: origin, originGamesPath: originGamesPath, gamesPath: gamesPath)
        }
        return true
    }

    /// A tap on the tab bar, even on Games, says where the person wants to be.
    func selectTabFromTabBar(_ tab: MainTab) {
        gameChatVisit = nil
        selectTab(tab)
    }

    /// The person closed the game's chat over the game, and it is out of sight. False when that
    /// ended a visit, so the game is no longer in front.
    func gameChatClosed(_ closing: GameChatClosing) -> Bool {
        guard let visit = gameChatVisit, visit.stage == .chat else { return true }
        switch closing {
        case .toGame:
            gameChatVisit?.stage = .game
            return true
        case .away:
            endGameChatVisit(visit)
            return false
        }
    }

    /// Back from the visit's game ends it. Any other change in Games makes the way back wrong.
    func gamesPathChanged(to path: [GamesDestination]) {
        guard let visit = gameChatVisit, path != visit.gamesPath else { return }
        if visit.stage == .game, path.count < visit.gamesPath.count, visit.gamesPath.starts(with: path) {
            endGameChatVisit(visit)
        } else {
            gameChatVisit = nil
        }
    }

    private func endGameChatVisit(_ visit: GameChatVisit) {
        gameChatVisit = nil
        selectTab(visit.origin)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { gamesPath = visit.originGamesPath }
    }

    /// Shows "Just us" after a tap inside the app: Message or a callout on the partner's avatar,
    /// the call's message button, or a message's banner. Already on screen, it stays. With no chat
    /// on screen, or only the game's chat that it closes, it slides over what is there. Another
    /// chat would stay open under it and mark the partner's messages read, so it opens in Chats.
    func showCoupleChat() {
        guard visibleChatSubject != .couple, !isCoupleChatSlidOver else { return }
        SwipeLessons[.justUs].openedWithButton(peeksCanShow: !reduceMotion)
        let chatOverGame = gameChatSheet.map { ThreadChatSubject.game($0.subject) }
        if visibleChatSubject == nil || visibleChatSubject == chatOverGame {
            gameChatVisit = nil
            // A game's chat still on its way would open under "Just us", or switch tabs under it.
            openingGameChatID = nil
            dismissGameChatSheet()
            isCoupleChatSlidOver = true
        } else {
            openCoupleChat()
        }
    }

    /// Opens the couple chat in Chats, over whatever that tab had pushed, for a push or a link
    /// from outside the app. Already open over the tabs, it stays there.
    func openCoupleChat() {
        guard !isCoupleChatSlidOver else { return }
        selectTab(.questions)
        dailyChatQuestion = nil
        gameChatDestination = nil
        questionsPath = []
        isCoupleChatRequested = true
    }

    /// The live summary feed supplies authorized previews even when APNs is unavailable. While the
    /// partner's avatar is on screen, the message shows in it instead of in a banner.
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
                // A call rang in the open app, which said how it ended.
                && summary.lastMessageCall == nil
                && visibleChatSubject != summary.subject
        }.sorted { ($0.lastMessageAt ?? .distantPast) < ($1.lastMessageAt ?? .distantPast) }
        for summary in arrivals {
            guard let preview = summary.lastMessagePreview, let messageID = summary.lastMessageID else { continue }
            let notice = PresenceMessageNotice(messageID: messageID, chat: summary.subject, preview: preview)
            if presenceModel.receive(.message(notice)) { continue }
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

    /// What tapping a partner message's banner or the partner's avatar opens: the chat it arrived in.
    func openChatAction(for subject: ThreadChatSubject) -> () -> Void {
        switch subject {
        case .game(let game): { openGameChat(kind: game.kind) }
        case .question(let id): { PaeoniaNotificationRouter.shared.route(.dailyChat(questionID: id)) }
        case .memory(let id): { PaeoniaNotificationRouter.shared.route(.memory(memoryID: id, showsComments: true)) }
        case .story(let id): { PaeoniaNotificationRouter.shared.route(.story(storyID: id, showsReplies: true)) }
        case .couple: { showCoupleChat() }
        }
    }
}
