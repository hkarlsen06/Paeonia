import SwiftUI

/// The cards `body` lays out.
extension PairedHomeView {
    /// The notices above the cards: access ending (`AccessNotice`), and a broken
    /// streak's free save day. Each stays closed once this person closes it.
    @ViewBuilder
    var notices: some View {
        if let accessNotice = shownAccessNotice {
            HomeAccessNoticeCard(notice: accessNotice) {
                dismissedAccessNoticeID = accessNotice.id
            }
            .transition(.opacity)
        }
        if let saveDeadline = shownStreakSaveDeadline {
            HomeStreakSaveCard(streak: dailyChallengeStreak, onTap: onTapStreak) {
                dismissedStreakSaveDeadline = saveDeadline.timeIntervalSince1970
            }
            .transition(.opacity)
        }
    }

    var shownAccessNotice: AccessNotice? {
        accessNotice.flatMap { $0.id == dismissedAccessNoticeID ? nil : $0 }
    }

    /// The end of the save day whose card shows, or nil when there is none or this person closed it.
    var shownStreakSaveDeadline: Date? {
        guard dailyChallengeStreak.isSavable, let deadline = dailyChallengeStreak.saveDeadline,
              deadline.timeIntervalSince1970 != dismissedStreakSaveDeadline else { return nil }
        return deadline
    }

    @ViewBuilder
    var unreadChatsCard: some View {
        if !unreadChats.isEmpty {
            HomeUnreadChatsCard(
                chats: unreadChats,
                partnerName: partnerName,
                partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                onOpenChat: onOpenChat
            )
            .transition(.opacity)
        }
    }

    /// A letter that waits is for this person to open, so it sits with the cards on the first screen.
    @ViewBuilder
    var waitingMailCard: some View {
        if let mail, !mail.waiting.isEmpty {
            HomeMailCard(mail: mail, partnerName: partnerName)
        }
    }

    /// The row that offers to write a letter, or to finish one. Nothing waits for the person
    /// here, so it goes under the tiles, where it takes no height from the map.
    @ViewBuilder
    var writeMailRow: some View {
        if let mail, mail.waiting.isEmpty {
            HomeMailCard(mail: mail, partnerName: partnerName)
        }
    }

    /// The recap on the anniversary itself, among the first cards, since the day calls for it.
    @ViewBuilder
    var anniversaryRecapCard: some View {
        if let recap, let shown = recap.homeRecap, recap.isAnniversaryToday(shown) {
            recapCard(shown, isAnniversaryToday: true)
        }
    }

    /// The recap on the days after, below the tiles, so it never takes room from the map.
    @ViewBuilder
    var laterRecapCard: some View {
        if let recap, let shown = recap.homeRecap, !recap.isAnniversaryToday(shown) {
            recapCard(shown, isAnniversaryToday: false)
        }
    }

    private func recapCard(_ shown: AnniversaryRecap, isAnniversaryToday: Bool) -> some View {
        HomeRecapCard(recap: shown, isAnniversaryToday: isAnniversaryToday) {
            recap?.presented = shown
        }
        .transition(.opacity)
    }

    /// Only the game the partner opened last. Whose turn it is belongs on the Games tab.
    @ViewBuilder
    var partnerGameCard: some View {
        if let games, let game = games.partnerGame,
           let card = game.card(games.cardContext(for: game.kind, isOnHub: false), open: onOpenGame) {
            card
                .id(game.kind)
                .transition(.opacity)
        }
    }

    var mapCard: some View {
        CoupleMapCard(
            currentName: currentName,
            currentProfilePhotoAssetID: currentProfilePhotoAssetID,
            partnerName: partnerName,
            partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
            state: locationMapState,
            onPromptCurrentLocation: onPromptCurrentLocation,
            onPauseSharing: onPauseLocationSharing,
            hearts: hearts,
            aspectRatio: isWideLayout ? 1 : 2
        )
    }

    /// An old question, drawing or memory, below the map.
    @ViewBuilder
    var lookBackCard: some View {
        if let lookBack, let item = lookBack.item {
            HomeLookBackCard(
                item: item,
                currentUserID: currentUserID,
                partnerName: partnerName,
                thumbnailLoader: lookBack.thumbnailLoader,
                onOpen: { onOpenLookBack(item) }
            )
            .transition(.opacity)
        }
    }

    /// The next visit, or the question of when the partners meet next.
    @ViewBuilder
    var visitCard: some View {
        if let visits {
            HomeVisitCard(visits: visits, streak: dailyChallengeStreak, isBelow: false)
        }
    }

    /// The question of when the partners meet next, after the person moved it to the bottom.
    @ViewBuilder
    var movedVisitPrompt: some View {
        if let visits {
            HomeVisitCard(visits: visits, streak: dailyChallengeStreak, isBelow: true)
        }
    }

    /// What both visit photo cards ask, for the page's change animation.
    var visitMemoryPrompts: [VisitMemoryPrompt] {
        guard let visits, let memories, let currentUserID else { return [] }
        return [true, false].compactMap { waiting in
            HomeVisitMemoryCard.prompt(
                visits: visits, memories: memories, viewerID: currentUserID, waiting: waiting, at: Date()
            )
        }
    }

    /// Where a memory saved from the visit photo card's form opens.
    func onOpenSavedMemory(_ open: @escaping (UUID) -> Void) -> Self {
        var view = self
        view.openSavedMemory = open
        return view
    }

    /// The partner's photos from a visit, waiting for this person's. Among the first cards.
    var waitingVisitMemoryCard: some View {
        visitMemoryCard(waiting: true)
    }

    /// The ask for photos from a visit. Under the tiles, where it takes no room from the map.
    var visitMemoryAsk: some View {
        visitMemoryCard(waiting: false)
    }

    @ViewBuilder
    private func visitMemoryCard(waiting: Bool) -> some View {
        if let visits, let memories, let currentUserID {
            HomeVisitMemoryCard(
                visits: visits, memories: memories, viewerID: currentUserID, partnerName: partnerName,
                waiting: waiting, onOpen: { visitMemoryForm = $0 }
            )
        }
    }

    @ViewBuilder
    var firstStepsCard: some View {
        if let firstSteps {
            HomeFirstStepsCard(
                steps: firstSteps,
                partnerName: partnerName,
                isCovered: isCovered,
                onOpen: onOpenFirstStep,
                onClose: onCloseFirstSteps,
                onFinished: onCloseFirstSteps
            )
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            // In front of the cards around it, so they don't hide the petals of its finish moment.
            .zIndex(1)
        }
    }

    /// PROTOTYPE: today's question in the state named by `-proto.home.daily`, for screenshots.
    var protoDailyState: DailyChallengeCardState? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-proto.home.daily") else { return nil }
        let prompt = "Hva er et lite øyeblikk med oss du tenker tilbake på?"
        let locked = [
            DailyChallengeCardState.LockedPartnerQuestion(id: UUID(), shortPrompt: "En favorittminne", daysAgo: 1),
            DailyChallengeCardState.LockedPartnerQuestion(id: UUID(), shortPrompt: "Drømmeturen deres", daysAgo: 2),
        ]
        return switch UserDefaults.standard.string(forKey: "proto.home.daily") {
        case "loading": DailyChallengeCardState(kind: .loading)
        case "noChallenge": DailyChallengeCardState(kind: .noChallenge)
        case "active": DailyChallengeCardState(kind: .active(prompt: prompt))
        case "activePartnerAnswered": DailyChallengeCardState(
            kind: .active(prompt: prompt), hasPartnerAnsweredToday: true
        )
        case "activeEarlier": DailyChallengeCardState(
            kind: .active(prompt: prompt), hasEarlierQuestionsToAnswer: true,
            lockedPartnerQuestions: locked, moreLockedPartnerQuestionCount: 3
        )
        case "completeWaiting": DailyChallengeCardState(kind: .complete)
        case "completeBoth": DailyChallengeCardState(kind: .complete, hasPartnerAnsweredToday: true)
        case "completeEarlier": DailyChallengeCardState(
            kind: .complete, hasPartnerAnsweredToday: true, hasEarlierQuestionsToAnswer: true,
            lockedPartnerQuestions: locked, moreLockedPartnerQuestionCount: 0
        )
        default: nil
        }
        #else
        nil
        #endif
    }

    var dailyPromptCard: some View {
        DailyPromptCard(
            state: protoDailyState ?? dailyChallengeCardState,
            partnerName: partnerName,
            partnerPhotoAssetID: partnerProfilePhotoAssetID,
            prefersPartnerAnswersWhenComplete: true,
            zoomNamespace: zoomNamespace,
            onAnswer: onOpenDailyChallenge,
            onOpenPartnerQuestion: onOpenPartnerQuestion
        )
        .zoomSource(DailyFlowZoom.us, in: zoomNamespace)
    }

    var cardsLayout: AnyLayout {
        isWideLayout
            ? AnyLayout(HomeWideLayout(spacing: PaeoniaSpacing.space16))
            : AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space16))
    }

    var currentName: String {
        currentDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationYouName)
    }

    var partnerName: String {
        partnerDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationPartnerName)
    }
}
