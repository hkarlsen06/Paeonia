#if DEBUG
import Foundation

/// The game Live Activity's views (`PaeoniaWidget/LiveActivity/GameLiveActivityViews.swift`) use
/// symbols of the widget's string catalog, which only the widget target generates. The Debug app
/// compiles those views for the `live-activity-views` scenario and reads the same strings from the
/// widget extension it embeds, so the scenario shows the widget's own copy.
nonisolated extension LocalizedStringResource {
    private static var widgetStrings: BundleDescription {
        .atURL(Bundle.main.bundleURL.appending(path: "PlugIns/PaeoniaWidgetExtension.appex"))
    }

    private static func widget(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, table: "Localizable", bundle: widgetStrings)
    }

    static var widgetLiveActivityJoin: LocalizedStringResource { widget("widget.liveActivity.join") }
    static var widgetLiveActivityJoinShort: LocalizedStringResource { widget("widget.liveActivity.joinShort") }
    static var widgetLiveActivityPlayShort: LocalizedStringResource { widget("widget.liveActivity.playShort") }
    static var widgetLiveActivityYourTurn: LocalizedStringResource { widget("widget.liveActivity.yourTurn") }
    static var widgetLiveActivityOpenToCheck: LocalizedStringResource { widget("widget.liveActivity.openToCheck") }
    static var widgetLiveActivityPartnerFallback: LocalizedStringResource {
        widget("widget.liveActivity.partnerFallback")
    }
    static var widgetGameLudo: LocalizedStringResource { widget("widget.game.ludo") }
    static var widgetGameDrawAndGuess: LocalizedStringResource { widget("widget.game.drawAndGuess") }
    static var widgetGameConnectFour: LocalizedStringResource { widget("widget.game.connectFour") }
    static var widgetGameMindMeld: LocalizedStringResource { widget("widget.game.mindMeld") }
    static var widgetGameConsensio: LocalizedStringResource { widget("widget.game.consensio") }
    static var widgetGameGuessMySpot: LocalizedStringResource { widget("widget.game.guessMySpot") }
    static var widgetGameDotsAndBoxes: LocalizedStringResource { widget("widget.game.dotsAndBoxes") }
    static var widgetGameUltimateTicTacToe: LocalizedStringResource { widget("widget.game.ultimateTicTacToe") }
    static var widgetGamePiccante: LocalizedStringResource { widget("widget.game.piccante") }
    static var widgetGameStoryChain: LocalizedStringResource { widget("widget.game.storyChain") }
    static var widgetGameExquisiteCorpse: LocalizedStringResource { widget("widget.game.exquisiteCorpse") }

    static func widgetLiveActivityWaitingFor(_ arg1: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "widget.liveActivity.waitingFor",
            defaultValue: "\(arg1)",
            table: "Localizable",
            bundle: widgetStrings
        )
    }

    static func widgetLiveActivityGameWith(_ arg1: String, _ arg2: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "widget.liveActivity.gameWith",
            defaultValue: "\(arg1)\(arg2)",
            table: "Localizable",
            bundle: widgetStrings
        )
    }

    static func widgetLiveActivityPlaying(_ arg1: String, _ arg2: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "widget.liveActivity.playing",
            defaultValue: "\(arg1)\(arg2)",
            table: "Localizable",
            bundle: widgetStrings
        )
    }

    static func widgetLiveActivityWasPlaying(_ arg1: String, _ arg2: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "widget.liveActivity.wasPlaying",
            defaultValue: "\(arg1)\(arg2)",
            table: "Localizable",
            bundle: widgetStrings
        )
    }
}
#endif
