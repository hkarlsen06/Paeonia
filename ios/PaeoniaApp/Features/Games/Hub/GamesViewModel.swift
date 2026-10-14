import Observation
import SwiftUI

/// A screen the Games tab can open.
nonisolated enum GamesDestination: Hashable, Sendable {
    /// A game's main screen. Hub cards, the Us tab card, deep links and pushes open it.
    case game(GameKind)

    // Each game adds its other screens below, named with its Swift prefix.

    /// "Our drawings".
    case drawAndGuessHistory
    case drawAndGuessHistoryDetail(UUID)

    /// "Our stories".
    case storyChainHistory
    case storyChainHistoryDetail(UUID)
    /// "Our melds".
    case mindMeldHistory
    case mindMeldHistoryDetail(UUID)
    /// "Our creatures".
    case exquisiteCorpseHistory
    case exquisiteCorpseHistoryDetail(UUID)
}

/// The Games tab: first-time setup, the hub, and the couple's game settings.
///
/// It reads the Games cache, which the live feeds keep current, so the hub shows
/// the last state at launch and offline. The settings and who has which game
/// open come from the shared overview. Each built game is in `games`.
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
    /// The setup and settings screens edit these.
    var draftPlayStyle: GamePlayStyle = .against
    var draftLanguage: GameLanguage = .preferred()
    var isSavingSettings = false
    var notice: GamesNotice?
    private(set) var partnerName: String
    /// The built games the partner has open right now, freshest first.
    private(set) var partnerGameKinds: [GameKind] = []

    // MARK: - Built games

    // Each built game adds its hub model here and to `games`.
    let drawAndGuess: DrawAndGuessHubModel
    let storyChain: StoryChainHubModel
    let mindMeld: MindMeldHubModel
    let exquisiteCorpse: ExquisiteCorpseHubModel
    let connectFour: BoardGameHubModel<ConnectFourBoard>
    let dotsAndBoxes: BoardGameHubModel<DotsAndBoxesBoard>
    let ultimateTicTacToe: BoardGameHubModel<UltimateTicTacToeBoard>

    /// The built games, in `GameKind` order. A kind that is not here shows nowhere.
    var games: [any GameHubModel] {
        [drawAndGuess, mindMeld, exquisiteCorpse, storyChain, connectFour, dotsAndBoxes, ultimateTicTacToe]
    }

    private let dependencies: GamesDependencies
    private var participants: GameParticipants
    private var overview: RemoteGamesOverview?
    private var hasLoaded = false

    init(dependencies: GamesDependencies, drawAndGuess: DrawAndGuessViewModel? = nil) {
        self.dependencies = dependencies
        participants = GameParticipants()
        partnerName = ""
        self.drawAndGuess = DrawAndGuessHubModel(dependencies: dependencies, game: drawAndGuess)
        storyChain = StoryChainHubModel(dependencies: dependencies)
        mindMeld = MindMeldHubModel(dependencies: dependencies)
        exquisiteCorpse = ExquisiteCorpseHubModel(dependencies: dependencies)
        connectFour = ConnectFourGame.hubModel(dependencies: dependencies)
        dotsAndBoxes = DotsAndBoxesGame.hubModel(dependencies: dependencies)
        ultimateTicTacToe = UltimateTicTacToeGame.hubModel(dependencies: dependencies)
    }

    /// A game waits for this person to move. The Games tab shows a badge.
    var isYourTurn: Bool {
        games.contains { $0.isYourTurn }
    }

    /// The hub's order: the game the partner is in first, then games waiting for
    /// this person, then catalog order.
    var hubGames: [any GameHubModel] {
        Self.hubOrder(
            games.map(\.kind),
            partnerGames: partnerGameKinds,
            yourTurn: Set(games.filter(\.isYourTurn).map(\.kind))
        ).compactMap { game($0) }
    }

    /// The game the partner opened most recently, while they have it open. The
    /// Us tab shows its card.
    var partnerGame: (any GameHubModel)? {
        partnerGameKinds.first.flatMap { game($0) }
    }

    func game(_ kind: GameKind) -> (any GameHubModel)? {
        games.first { $0.kind == kind }
    }

    func partnerIsHere(in kind: GameKind) -> Bool {
        partnerGameKinds.contains(kind)
    }

    /// What a game's card needs from the tab.
    func cardContext(for kind: GameKind, isOnHub: Bool) -> GameHubCardContext {
        GameHubCardContext(partnerName: partnerName, partnerIsHere: partnerIsHere(in: kind), isOnHub: isOnHub)
    }

    /// The screen for a destination, from the game that owns it.
    func screen(for destination: GamesDestination) -> AnyView? {
        games.lazy.compactMap { $0.screen(for: destination) }.first
    }

    private var currentUserID: UUID? {
        participants.currentUserID
    }

    func configure(participants newParticipants: GameParticipants) {
        let userChanged = participants.currentUserID != newParticipants.currentUserID
        participants = newParticipants
        partnerName = newParticipants.partnerName
        for game in games {
            game.configure(participants: newParticipants)
        }
        if userChanged {
            hasLoaded = false
            overview = nil
            partnerGameKinds = []
            screen = .loading
        }
    }

    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        for game in games {
            game.setLocalChangeSyncHandler(handler)
        }
    }

    // MARK: - Reading

    /// Reads the cache, and the server when the cache is empty.
    func load() async {
        await reload()
        if overview == nil {
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
        overview = document.overview
        hasLoaded = true
        partnerGameKinds = Self.partnerGames(in: overview, now: dependencies.now())
            .filter { game($0) != nil }
        settings = overview?.settings
        if let settings {
            draftPlayStyle = settings.playStyle
            draftLanguage = settings.language
        }
        for game in games {
            await game.reload()
            let gameNotice = await game.takeNotice()
            if notice == nil, let gameNotice {
                notice = gameNotice
            }
        }
        await updateScreen(userID: userID)
    }

    /// Reads the server's overview and every game's state once and caches them.
    func refresh() async {
        guard let userID = currentUserID else { return }
        for game in games {
            await game.refresh()
        }
        do {
            let gateway = dependencies.gateway
            guard try await dependencies.cache.fetchOverview(from: gateway, ownerUserID: userID) else { return }
            await reload()
        } catch {
            await reload()
            // A read that was cancelled (the tab changed under it) says nothing about the network.
            if overview == nil, hasLoaded, !Task.isCancelled, !(error is CancellationError),
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
            screen = overview == nil ? .loading : .setup
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
        // Read the overview and the games again, so the hub and every game agree.
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

extension GamesViewModel {
    /// The games the partner has open, the most recent heartbeat first.
    nonisolated static func partnerGames(in overview: RemoteGamesOverview?, now: Date) -> [GameKind] {
        (overview?.presence ?? [])
            .filter { GamePresence.isFresh($0.partnerLastSeenAt, now: now) }
            .sorted { ($0.partnerLastSeenAt ?? .distantPast) > ($1.partnerLastSeenAt ?? .distantPast) }
            .map(\.kind)
    }

    /// The games the partner is in, then the games waiting for this person in
    /// catalog order, then the rest in catalog order.
    nonisolated static func hubOrder(
        _ kinds: [GameKind],
        partnerGames: [GameKind],
        yourTurn: Set<GameKind>
    ) -> [GameKind] {
        let catalog = GameKind.allCases.filter(kinds.contains)
        let rest = catalog.filter { !partnerGames.contains($0) }
        return partnerGames.filter(catalog.contains) + rest.filter(yourTurn.contains)
            + rest.filter { !yourTurn.contains($0) }
    }
}
