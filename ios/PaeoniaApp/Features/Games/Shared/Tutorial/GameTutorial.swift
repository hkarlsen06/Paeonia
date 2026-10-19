import SwiftUI

/// A game's "How to play" cards. Only games whose rules are hard to pick up by
/// playing have them, so `init` fails for every other kind.
struct GameTutorial {
    struct Page: Identifiable {
        let image: ImageResource
        let title: LocalizedStringResource
        let message: LocalizedStringResource

        var id: String { title.key }
    }

    let kind: GameKind
    let pages: [Page]

    init?(kind: GameKind, partnerName: String) {
        switch kind {
        case .ultimateTicTacToe: pages = Self.ultimateTicTacToePages(partnerName: partnerName)
        case .dotsAndBoxes: pages = Self.dotsAndBoxesPages(partnerName: partnerName)
        case .mindMeld: pages = Self.mindMeldPages(partnerName: partnerName)
        case .consensio: pages = Self.consensioPages(partnerName: partnerName)
        case .guessMySpot: pages = Self.guessMySpotPages(partnerName: partnerName)
        case .drawAndGuess, .exquisiteCorpse, .storyChain, .connectFour, .ludo: return nil
        }
        self.kind = kind
    }

    private static func ultimateTicTacToePages(partnerName: String) -> [Page] {
        [
            Page(
                image: .gameTutorialUltimateGoal,
                title: .gamesTutorialUltimateGoalTitle,
                message: .gamesTutorialUltimateGoalMessage
            ),
            Page(
                image: .gameTutorialUltimateSend,
                title: .gamesTutorialUltimateSendTitle(partnerName),
                message: .gamesTutorialUltimateSendMessage(partnerName)
            ),
            Page(
                image: .gameTutorialUltimateAnywhere,
                title: .gamesTutorialUltimateAnywhereTitle,
                message: .gamesTutorialUltimateAnywhereMessage
            ),
        ]
    }

    private static func dotsAndBoxesPages(partnerName: String) -> [Page] {
        [
            Page(
                image: .gameTutorialDotsLine,
                title: .gamesTutorialDotsLineTitle,
                message: .gamesTutorialDotsLineMessage(partnerName)
            ),
            Page(
                image: .gameTutorialDotsBox,
                title: .gamesTutorialDotsBoxTitle,
                message: .gamesTutorialDotsBoxMessage
            ),
            Page(
                image: .gameTutorialDotsPhoto,
                title: .gamesTutorialDotsPhotoTitle,
                message: .gamesTutorialDotsPhotoMessage
            ),
        ]
    }

    private static func mindMeldPages(partnerName: String) -> [Page] {
        [
            Page(
                image: .gameTutorialMindMeldWords,
                title: .gamesTutorialMindMeldWordsTitle,
                message: .gamesTutorialMindMeldWordsMessage(partnerName)
            ),
            Page(
                image: .gameTutorialMindMeldConnect,
                title: .gamesTutorialMindMeldConnectTitle,
                message: .gamesTutorialMindMeldConnectMessage
            ),
            Page(
                image: .gameTutorialMindMeldMatch,
                title: .gamesTutorialMindMeldMatchTitle,
                message: .gamesTutorialMindMeldMatchMessage
            ),
        ]
    }

    private static func consensioPages(partnerName: String) -> [Page] {
        [
            Page(
                image: .gameTutorialConsensioPlace,
                title: .gamesTutorialConsensioPlaceTitle,
                message: .gamesTutorialConsensioPlaceMessage
            ),
            Page(
                image: .gameTutorialConsensioGuess,
                title: .gamesTutorialConsensioGuessTitle(partnerName),
                message: .gamesTutorialConsensioGuessMessage(partnerName)
            ),
            Page(
                image: .gameTutorialConsensioClose,
                title: .gamesTutorialConsensioCloseTitle,
                message: .gamesTutorialConsensioCloseMessage
            ),
        ]
    }

    private static func guessMySpotPages(partnerName: String) -> [Page] {
        [
            Page(
                image: .gameTutorialGuessMySpotSend,
                title: .gamesTutorialGuessMySpotSendTitle,
                message: .gamesTutorialGuessMySpotSendMessage
            ),
            Page(
                image: .gameTutorialGuessMySpotGuess,
                title: .gamesTutorialGuessMySpotGuessTitle(partnerName),
                message: .gamesTutorialGuessMySpotGuessMessage(partnerName)
            ),
            Page(
                image: .gameTutorialGuessMySpotClose,
                title: .gamesTutorialGuessMySpotCloseTitle,
                message: .gamesTutorialGuessMySpotCloseMessage
            ),
        ]
    }

    /// Whether this phone has shown the cards for this game. It is per phone, not
    /// per account, which is enough for a one-time explanation.
    var hasBeenShown: Bool {
        get { UserDefaults.standard.bool(forKey: seenKey) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }

    private var seenKey: String { "paeonia.games.tutorialShown.v1.\(kind.rawValue)" }
}
