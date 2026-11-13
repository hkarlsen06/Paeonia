import SwiftUI

/// The cards that come and go above the tiles, most urgent first. On the map layout only the
/// first one with something to show sits above the tiles. The rest go under them, so the map
/// keeps its height however many there are.
enum HomePopUpCard: CaseIterable, Hashable {
    case accessNotice
    case streakSave
    case partnerGame
    case unreadChats
    case anniversaryRecap
    case waitingMail
    case firstSteps
    case visit
    case waitingVisitMemory

    /// The notices and the partner's game come before today's question, the rest after it.
    var leadsDailyQuestion: Bool {
        switch self {
        case .accessNotice, .streakSave, .partnerGame: true
        default: false
        }
    }
}

extension PairedHomeView {
    /// The pop-up cards with something to show, most urgent first.
    var shownPopUps: [HomePopUpCard] {
        HomePopUpCard.allCases.filter(isShown)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func isShown(_ card: HomePopUpCard) -> Bool {
        switch card {
        case .accessNotice:
            shownAccessNotice != nil
        case .streakSave:
            shownStreakSaveDeadline != nil
        case .partnerGame:
            partnerGameView != nil
        case .unreadChats:
            !unreadChats.isEmpty
        case .anniversaryRecap:
            recap.flatMap { recap in recap.homeRecap.map(recap.isAnniversaryToday) } ?? false
        case .waitingMail:
            !(mail?.waiting.isEmpty ?? true)
        case .firstSteps:
            firstSteps != nil
        case .visit:
            switch visits?.homeCard(at: visitNow, streak: dailyChallengeStreak) {
            case .prompt, .visit, .together: true
            case .hidden, .movedPrompt, nil: false
            }
        case .waitingVisitMemory:
            hasWaitingVisitMemory
        }
    }

    /// The first pop-up card, on the side of today's question it belongs on.
    @ViewBuilder
    func leadPopUp(_ lead: HomePopUpCard?, beforeQuestion: Bool) -> some View {
        if let lead, lead.leadsDailyQuestion == beforeQuestion {
            popUpCard(lead)
        }
    }

    /// The pop-up cards after the first, under the tiles.
    func laterPopUps(_ popUps: [HomePopUpCard]) -> some View {
        ForEach(popUps.dropFirst(), id: \.self) { card in
            popUpCard(card)
        }
    }

    @ViewBuilder
    // swiftlint:disable:next cyclomatic_complexity
    func popUpCard(_ card: HomePopUpCard) -> some View {
        switch card {
        case .accessNotice: accessNoticeCard
        case .streakSave: streakSaveCard
        case .partnerGame: partnerGameCard
        case .unreadChats: unreadChatsCard
        case .anniversaryRecap: anniversaryRecapCard
        case .waitingMail: waitingMailCard
        case .firstSteps: firstStepsCard
        case .visit: visitCard
        case .waitingVisitMemory: waitingVisitMemoryCard
        }
    }
}
