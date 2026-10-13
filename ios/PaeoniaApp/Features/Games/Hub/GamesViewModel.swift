import Observation
import SwiftUI

/// A screen the Games tab can open.
nonisolated enum GamesDestination: Hashable, Sendable {
    case drawAndGuess
}

/// The Games tab: first-time setup, the hub, and the couple's game settings.
///
/// It reads the Games cache, which the live feed keeps current, so the hub shows
/// the last state at launch and offline. Draw & Guess itself is
/// `drawAndGuess`, built once so a notification that opens the game finds it
/// ready.
@MainActor
@Observable
final class GamesViewModel {
    enum Screen: Equatable {
        /// Nothing cached yet and the first read has not finished.
        case loading
        /// Nothing cached and the first read failed.
        case unavailable
        /// The couple has not chosen a play style and language.
        case setup
        /// The partner chose first. Shows what they picked once.
        case partnerPicked(RemoteGameSettings)
        case hub
    }

    var screen: Screen = .loading
    var settings: RemoteGameSettings?
    var hubSummary: DrawAndGuessHubSummary?
    /// The setup and settings screens edit these.
    var draftPlayStyle: GamePlayStyle = .against
    var draftLanguage: GameLanguage = .preferred()
    var isSavingSettings = false
    var notice: GamesNotice?
    private(set) var partnerName: String

    let drawAndGuess: DrawAndGuessViewModel

    private let dependencies: GamesDependencies
    private var participants: DrawAndGuessParticipants
    private var state: RemoteDrawAndGuessState?
    private var hasLoaded = false

    init(dependencies: GamesDependencies, drawAndGuess: DrawAndGuessViewModel? = nil) {
        self.dependencies = dependencies
        participants = DrawAndGuessParticipants()
        partnerName = ""
        self.drawAndGuess = drawAndGuess ?? DrawAndGuessViewModel(dependencies: dependencies)
    }

    /// A game waits for this person to draw or guess. The Games tab shows a badge.
    var isYourTurn: Bool {
        hubSummary?.status == .yourTurnToDraw || hubSummary?.status == .yourTurnToGuess
    }

    private var currentUserID: UUID? {
        participants.currentUserID
    }

    func configure(participants newParticipants: DrawAndGuessParticipants) {
        let userChanged = participants.currentUserID != newParticipants.currentUserID
        participants = newParticipants
        partnerName = newParticipants.partnerName
        drawAndGuess.configure(participants: newParticipants)
        if userChanged {
            hasLoaded = false
            state = nil
            screen = .loading
        }
    }

    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        drawAndGuess.setLocalChangeSyncHandler(handler)
    }

    // MARK: - Reading

    /// Reads the cache, and the server when the cache is empty.
    func load() async {
        await reload()
        if state == nil {
            await refresh()
        }
    }

    /// Follows writes to the Games cache and the pending operations.
    func observeStoreChanges() async {
        for await change in LocalStoreChanges.changes(in: .games, .pendingOperations) {
            guard !Task.isCancelled else { return }
            guard change.ownerUserID == nil || change.ownerUserID == currentUserID else { continue }
            await reload()
        }
    }

    func reload() async {
        guard let userID = currentUserID else { return }
        let document = await dependencies.cache.document(ownerUserID: userID)
        guard currentUserID == userID else { return }
        let pending = await DrawAndGuessPendingWork.load(
            from: dependencies.pendingOperationStore,
            ownerUserID: userID
        ) ?? .none
        state = document.state
        hasLoaded = true
        settings = document.state?.settings
        if let settings {
            draftPlayStyle = settings.playStyle
            draftLanguage = settings.language
        }
        if let stored = await dependencies.cache.takeNotices(ownerUserID: userID).last, notice == nil {
            notice = GamesNotice(stored)
        }
        hubSummary = document.state.map { state in
            let resolution = DrawAndGuessResolver(userID: userID).resolve(
                state: state,
                pending: pending,
                acknowledgedRoundIDs: Set(document.acknowledgedRoundIDs),
                isPartnerDrawingLive: false
            )
            return DrawAndGuessHubSummary(state: state, resolution: resolution, now: dependencies.now())
        }
        await updateScreen(userID: userID)
    }

    /// Reads the server's state once and caches it.
    func refresh() async {
        guard let userID = currentUserID else { return }
        do {
            let gateway = dependencies.gateway
            guard try await dependencies.cache.fetchState(from: gateway, ownerUserID: userID) else { return }
            await reload()
        } catch {
            // A read that was cancelled (the tab changed under it) says nothing about the network.
            if state == nil, hasLoaded, !Task.isCancelled, !(error is CancellationError),
               (error as? URLError)?.code != .cancelled {
                screen = .unavailable
            }
        }
    }

    private func updateScreen(userID: UUID) async {
        guard hasLoaded else {
            screen = .loading
            return
        }
        guard let settings else {
            screen = state == nil ? .loading : .setup
            return
        }
        if await dependencies.cache.hasSeenSettings(coupleID: settings.coupleID, ownerUserID: userID) {
            screen = .hub
        } else if settings.updatedByUserID == userID {
            // This person chose them, so there is nothing new to show.
            await dependencies.cache.markSettingsSeen(coupleID: settings.coupleID, ownerUserID: userID)
            screen = .hub
        } else {
            screen = .partnerPicked(settings)
        }
    }

    // MARK: - Settings

    /// Saves the first choices from setup.
    func finishSetup() async {
        await saveSettings(playStyle: draftPlayStyle, language: draftLanguage)
    }

    /// Saves a change from the settings sheet. Returns whether it saved.
    @discardableResult
    func saveSettings(playStyle: GamePlayStyle, language: GameLanguage) async -> Bool {
        guard !isSavingSettings, let userID = currentUserID else { return false }
        isSavingSettings = true
        defer { isSavingSettings = false }
        let saved: RemoteGameSettings
        do {
            saved = try await dependencies.gateway.setSettings(playStyle: playStyle, language: language)
        } catch {
            notice = .couldNotSaveSettings
            return false
        }
        await dependencies.cache.markSettingsSeen(coupleID: saved.coupleID, ownerUserID: userID)
        // The settings come back with the state, so the hub and the game agree.
        await refresh()
        return true
    }

    /// "Sounds good" on the moment that shows what the partner picked.
    func acknowledgePartnerPicked() async {
        guard let userID = currentUserID, let settings else { return }
        await dependencies.cache.markSettingsSeen(coupleID: settings.coupleID, ownerUserID: userID)
        await reload()
    }

    func clearNotice() {
        notice = nil
    }
}
