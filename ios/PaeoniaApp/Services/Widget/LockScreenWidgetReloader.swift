import Foundation
import UIKit
// WidgetCenter is not marked Sendable, but reloading from the main actor is safe.
@preconcurrency import WidgetKit

/// Asks WidgetKit to rebuild the widgets that read the shared snapshot: the Lock
/// Screen ones and the Home Screen ones except the drawing. The widgets fetch their
/// own data from the server, so reload only after the server already has the change.
/// These widgets are hidden while Paeonia is open, so the app reloads them
/// once as it leaves the foreground instead of after every change.
nonisolated enum LockScreenWidgetReloader {
    static func reload() {
        // Marks the cache old, so the reload fetches even right after another one.
        UserDefaults(suiteName: PaeoniaAppGroup.identifier)?
            .set(Date(), forKey: LockScreenCache.invalidatedAtKey)
        Task { @MainActor in
            for kind in SnapshotWidgetKind.all {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }
    }

    /// For a write the server accepted. While the app is open the reload as it
    /// leaves covers it, so this only reloads when the app is not in front.
    static func reloadIfNotActive() {
        Task { @MainActor in
            guard UIApplication.shared.applicationState != .active else { return }
            reload()
        }
    }
}

nonisolated extension SyncPendingOperationKind {
    /// Whether a successful write of this kind changes what a snapshot widget
    /// shows: the start date, countdowns and birthdays, the daily answer (and so the streak),
    /// location sharing, and any move in a game.
    var changesLockScreenWidgets: Bool {
        switch self {
        case .setRelationshipStartedOn,
             .saveCountdown, .deleteCountdown, .setBirthday,
             .submitDailyAnswer,
             .updateLocationSharingPreference,
             .pickDrawWord, .submitGameDrawing, .submitGameGuess, .giveUpGameRound,
             .storyChainStartStory, .storyChainAddLine,
             .lockMindMeldWord, .countMindMeldRound,
             .placeConsensioSpot, .guessConsensioSpot,
             .guessMySpotSend, .guessMySpotGuess,
             .exquisiteCorpseSubmitPart,
             .boardGameMove, .boardGameRematch:
            true
        default:
            false
        }
    }
}
