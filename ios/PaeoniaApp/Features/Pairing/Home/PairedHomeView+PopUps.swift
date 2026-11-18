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
            // A new lead is a new view, so the old one leaves and the new one arrives with
            // the transition instead of one view swapping its content.
            popUpSlot(lead)
                .id(lead)
        }
    }

    /// The pop-up cards after the first, under the tiles.
    func laterPopUps(_ popUps: [HomePopUpCard]) -> some View {
        ForEach(popUps.dropFirst(), id: \.self, content: popUpSlot)
    }

    /// The card in one view of its own. A card is a conditional view, and on one of those
    /// the transition would reach the views inside it, whose own fade then wins.
    private func popUpSlot(_ card: HomePopUpCard) -> some View {
        VStack(spacing: 0) {
            popUpCard(card)
        }
        .transition(.homePopUpSlot)
    }

    @ViewBuilder
    // swiftlint:disable:next cyclomatic_complexity
    private func popUpCard(_ card: HomePopUpCard) -> some View {
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

extension AnyTransition {
    /// A pop-up card that takes the lead leaves the footer under the tiles and shows up
    /// above them, in a different stack. Flying it there pulls it across the tiles. It
    /// fades out early in the page's glide, and fades in late, once the cards gliding past
    /// its new place are by.
    fileprivate static let homePopUpSlot = AnyTransition.modifier(
        active: PartialFade(progress: 0, start: 0.7), identity: PartialFade(progress: 1, start: 0.7)
    )
}

/// Fully clear until the animation passes `start`, then fully shown at its end. Going the
/// other way, it is clear once the animation is back to `start`.
private struct PartialFade: ViewModifier, Animatable {
    var progress: Double
    let start: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(max(0, (progress - start) / (1 - start)))
    }
}
