import SwiftUI

/// The cards `body` lays out.
extension PairedHomeView {
    /// The notices above the cards: access ending (`AccessNotice`), and a broken
    /// streak's free save day.
    @ViewBuilder
    var notices: some View {
        if let accessNotice {
            HomeAccessNoticeCard(notice: accessNotice)
                .transition(.opacity)
        }
        if dailyChallengeStreak.isSavable {
            HomeStreakSaveCard(streak: dailyChallengeStreak, onTap: onTapStreak)
        }
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
        .zoomSource(DailyFlowZoom.home, in: zoomNamespace)
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
