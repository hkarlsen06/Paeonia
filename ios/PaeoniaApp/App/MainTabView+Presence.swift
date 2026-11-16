import SwiftUI

/// The identity of the task that runs the presence model. A new couple, or the app coming back to
/// the foreground, starts it again.
struct PresenceRunKey: Hashable {
    var coupleID: UUID?
    var isInForeground: Bool
}

/// The partner's avatar over every screen (`Features/Presence`).
extension MainTabView {
    var presenceModel: PartnerPresenceModel { models.presence }

    /// The tabs with "Just us" that pulls in from the right edge, under the call overlay. The overlay
    /// is outside "Just us", so its composer keeps the avatar and the bubble clear, and its call
    /// button has the starter.
    var tabsUnderOverlays: some View {
        tabNavigation
            .coupleChatSlideOver(
                isPresented: $isCoupleChatSlidOver, isEnabled: allowsCoupleChatSwipe, peeks: coupleChatPeekIsWelcome
            )
            .callOverlay(participants: dailyChallengeParticipants, presence: presenceModel)
    }

    /// Runs the presence model while the app is in front, keeps it told what is on screen, and opens
    /// what the avatar asks for. The model is in the environment for Settings.
    func runningPresence(on content: some View) -> some View {
        content
            .environment(presenceModel)
            .task(id: presenceRunKey) { await runPresence(presenceRunKey) }
            .onChange(of: presenceViewer, initial: true) { _, viewer in presenceModel.viewer = viewer }
            .onChange(of: unreadPartnerChats, initial: true) { _, count in presenceModel.unreadChats = count }
            // A notification from the partner that arrives while the app is open shows in the avatar.
            .onAppear {
                PaeoniaNotificationRouter.shared.takePartnerNotices(for: presenceModel) { [presenceModel] notice in
                    presenceModel.receiveNow(.update(notice))
                }
            }
            .onDisappear { PaeoniaNotificationRouter.shared.stopTakingPartnerNotices(for: presenceModel) }
            .onChange(of: presenceModel.openRequest) { _, request in
                if request != nil { openPresenceRequest() }
            }
            // The full call screen covers the game, so it says when a game newly needs this person.
            .onChange(of: gamesViewModel.needs) { previous, current in
                let openGame = presenceModel.viewer.openGame
                guard let news = GameNeed.newlyNeeded(previous: previous, current: current, openGame: openGame)
                else { return }
                presenceModel.gameNeedsYou(news.kind, news.need)
            }
    }

    /// A short trip to Control Center or a system alert keeps the session. Leaving for the
    /// background ends it, and the partner sees this person go.
    private var presenceRunKey: PresenceRunKey {
        PresenceRunKey(coupleID: identity.coupleID, isInForeground: scenePhase != .background)
    }

    private func runPresence(_ key: PresenceRunKey) async {
        guard key.isInForeground, let coupleID = key.coupleID else { return }
        await presenceModel.run(coupleID: coupleID)
    }

    /// The chats where the partner wrote something this person has not read, as the Chats list counts
    /// them, leaving out the one on screen, which reads it.
    private var unreadPartnerChats: Int {
        chatSummaries.summaries.keys.count { $0 != visibleChatSubject && chatSummaries.isUnread($0) }
    }

    /// What this person has on screen, so the avatar leaves out the chat and the game they are in.
    private var presenceViewer: PresenceViewerPlace {
        let openGame = selection.wrappedValue == .games ? gamesPath.last?.gameKind : nil
        return PresenceViewerPlace(
            visibleChat: visibleChatSubject,
            openGame: openGame,
            gameChat: identity.coupleID.flatMap { coupleID in
                openGame.map { GameChatSubject(coupleID: coupleID, kind: $0) }
            },
            // Open on the Us tab whichever tab shows, so a trip to another tab doesn't tell the
            // partner again that this person opened it.
            isDrawing: widgetDrawingPresented.wrappedValue
        )
    }

    /// Opens what a tap on the partner's avatar asked for. The avatar has closed the sheets and
    /// covers over the tabs first.
    private func openPresenceRequest() {
        switch presenceModel.takeOpenRequest() {
        case .chat(.couple):
            // With no chat on screen, or only the game's chat that it closes, "Just us" slides over
            // what is there. Another chat would stay open under it and mark the partner's messages
            // read, so it opens in Chats instead.
            let chatOverGame = gameChatSheet.map { ThreadChatSubject.game($0.subject) }
            if visibleChatSubject == nil || visibleChatSubject == chatOverGame {
                slideOverCoupleChat()
            } else {
                openCoupleChat()
            }
        case let .chat(subject):
            openChatAction(for: subject)()
        case let .game(kind):
            isCoupleChatSlidOver = false
            dismissGameChatSheet()
            openGameFromHome(.game(kind))
        case .drawing:
            isCoupleChatSlidOver = false
            dismissGameChatSheet()
            actions.openWidgetDrawing()
        case let .link(link):
            isCoupleChatSlidOver = false
            PaeoniaNotificationRouter.shared.route(link)
        case nil:
            break
        }
    }

    /// "Just us" slides over whatever is on screen, without a switch of tab.
    private func slideOverCoupleChat() {
        dismissGameChatSheet()
        isCoupleChatSlidOver = true
    }
}
