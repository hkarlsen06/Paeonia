import Observation
import SwiftUI

/// A screen the Games tab can open.
nonisolated enum GamesDestination: Hashable, Sendable {
    /// A game's main screen. Hub cards, the Home tab card, deep links and pushes open it.
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
    /// "What we know".
    case consensioHistory
    case consensioHistoryDetail(UUID)
    /// "Our guesses".
    case guessMySpotHistory
    /// "Our creatures".
    case exquisiteCorpseHistory
    case exquisiteCorpseHistoryDetail(UUID)
    /// A board game's "Past games", and one of them played again.
    case boardGameHistory(GameKind)
    case boardGameReplay(GameKind, gameNumber: Int)
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
        /// Nothing cached and the first read failed, for this reason.
        case unavailable(PaeoniaFailure)
        case hub
    }

    /// The steps before this person's first game, in one sheet over the hub.
    enum IntroStep {
        /// The couple has not chosen a play style and language.
        case setup
        /// The partner chose first. Shows what they picked once.
        case partnerPicked(RemoteGameSettings)
        /// The canvas for the mark on this person's pieces, for someone without one.
        case mark(BoardMarkEditorModel)
    }

    var screen: Screen = .loading
    var settings: RemoteGameSettings?
    /// The setup and settings screens edit these.
    var draftPlayStyle: GamePlayStyle = .against
    var draftLanguage: GameLanguage = .preferred()
    var isSavingSettings = false
    var notice: GamesNotice?
    /// The first-time step on screen while a game waits to open.
    var introStep: IntroStep?
    /// A screen to push now. The Games tab pushes it and clears this.
    var destinationToOpen: GamesDestination?
    private(set) var partnerName: String
    /// The built games the partner has open right now, freshest first.
    private(set) var partnerGameKinds: [GameKind] = []

    // MARK: - Built games

    // Each built game adds its hub model here and to `games`.
    let drawAndGuess: DrawAndGuessHubModel
    let storyChain: StoryChainHubModel
    let mindMeld: MindMeldHubModel
    let consensio: ConsensioHubModel
    let guessMySpot: GuessMySpotHubModel
    let exquisiteCorpse: ExquisiteCorpseHubModel
    let connectFour: BoardGameHubModel<ConnectFourBoard>
    let dotsAndBoxes: BoardGameHubModel<DotsAndBoxesBoard>
    let ultimateTicTacToe: BoardGameHubModel<UltimateTicTacToeBoard>
    let ludo: BoardGameHubModel<LudoBoard>

    /// The built games, in `GameKind` order. A kind that is not here shows nowhere.
    var games: [any GameHubModel] {
        [
            ludo, drawAndGuess, connectFour, mindMeld, consensio, guessMySpot, dotsAndBoxes, ultimateTicTacToe,
            storyChain, exquisiteCorpse,
        ]
    }

    private let dependencies: GamesDependencies
    private var participants: GameParticipants
    private var overview: RemoteGamesOverview?
    private var hasLoaded = false
    /// The step the next opened game shows first, or nil when there is none.
    private var neededIntro: IntroStep?
    /// The game that opens when the first-time steps end.
    private var destinationAfterIntro: GamesDestination?

    init(dependencies: GamesDependencies, drawAndGuess: DrawAndGuessViewModel? = nil) {
        self.dependencies = dependencies
        participants = GameParticipants()
        partnerName = ""
        self.drawAndGuess = DrawAndGuessHubModel(dependencies: dependencies, game: drawAndGuess)
        storyChain = StoryChainHubModel(dependencies: dependencies)
        mindMeld = MindMeldHubModel(dependencies: dependencies)
        consensio = ConsensioHubModel(dependencies: dependencies)
        guessMySpot = GuessMySpotHubModel(dependencies: dependencies)
        exquisiteCorpse = ExquisiteCorpseHubModel(dependencies: dependencies)
        connectFour = ConnectFourGame.hubModel(dependencies: dependencies)
        dotsAndBoxes = DotsAndBoxesGame.hubModel(dependencies: dependencies)
        ultimateTicTacToe = UltimateTicTacToeGame.hubModel(dependencies: dependencies)
        ludo = LudoGame.hubModel(dependencies: dependencies)
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
    /// Home tab shows its card.
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

    func reload() async {
        guard let userID = currentUserID else { return }
        let document = await dependencies.cache.document(ownerUserID: userID)
        guard currentUserID == userID else { return }
        overview = document.overview
        hasLoaded = true
        let newPartnerGameKinds = Self.partnerGames(in: overview)
            .filter { game($0) != nil }
        if partnerGameKinds != newPartnerGameKinds {
            partnerGameKinds = newPartnerGameKinds
        }
        if settings != overview?.settings {
            settings = overview?.settings
            if let settings {
                draftPlayStyle = settings.playStyle
                draftLanguage = settings.language
            }
        }
        for game in games {
            await game.reload()
            let gameNotice = await game.takeNotice()
            if notice == nil, let gameNotice {
                notice = gameNotice
            }
        }
        updateScreen(userID: userID)
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
                screen = .unavailable(PaeoniaFailure(error))
            }
        }
    }

    private func updateScreen(userID: UUID) {
        guard hasLoaded else {
            screen = .loading
            return
        }
        guard let settings else {
            neededIntro = .setup
            screen = overview == nil ? .loading : .hub
            return
        }
        // Whoever chose them has seen them. The server keeps who else has.
        neededIntro = settings.seenByUserIDs.contains(userID) || settings.updatedByUserID == userID
            ? nil
            : .partnerPicked(settings)
        screen = .hub
    }

    // MARK: - Opening

    /// Opens a screen from the hub, Home or a notification. The hub shows every
    /// game before anyone sets anything up, so the first game opened shows the
    /// first-time steps, and the game opens after them.
    func open(_ destination: GamesDestination) {
        guard screen == .hub else { return }
        if case .game = destination, let neededIntro {
            destinationAfterIntro = destination
            introStep = neededIntro
        } else {
            destinationToOpen = destination
        }
    }

    /// "Change" on what the partner picked switches the sheet to the setup step,
    /// which starts from the partner's choices.
    func changePartnerPicked() {
        guard case .partnerPicked = introStep else { return }
        introStep = .setup
    }

    /// The sheet closed. Closing the mark step still opens the game, because the
    /// mark can wait. Closing an earlier step leaves the person on the hub.
    func introDismissed() {
        if case .mark = introStep {
            destinationToOpen = destinationAfterIntro
        }
        introStep = nil
        destinationAfterIntro = nil
    }

    /// After the settings, someone without a mark gets the canvas. Without one
    /// to ask for, the game opens.
    private func continueIntro() async {
        guard introStep != nil else { return }
        let editor = await makeMarkEditor()
        // The person closed the sheet while the marks loaded.
        guard introStep != nil else { return }
        if let editor, !editor.hasSavedMark {
            introStep = .mark(editor)
        } else {
            destinationToOpen = destinationAfterIntro
            introStep = nil
            destinationAfterIntro = nil
        }
    }

    // MARK: - Settings

    /// Saves the first choices from setup, then moves on to the mark.
    func finishSetup() async {
        if await saveSettings(playStyle: draftPlayStyle, language: draftLanguage) {
            await continueIntro()
        }
    }

    /// Saves a change from the settings sheet. Returns whether it saved.
    @discardableResult
    func saveSettings(playStyle: GamePlayStyle, language: GameLanguage) async -> Bool {
        guard !isSavingSettings, currentUserID != nil else { return false }
        isSavingSettings = true
        defer { isSavingSettings = false }
        do {
            _ = try await dependencies.gateway.setSettings(playStyle: playStyle, language: language)
        } catch {
            notice = .couldNotSaveSettings(PaeoniaFailure(error))
            return false
        }
        // Read the overview and the games again, so the hub and every game agree.
        await refresh()
        return true
    }

    /// "Sounds good" on the moment that shows what the partner picked.
    /// When that does not reach the server, the game still opens, and the moment
    /// shows again before the next game.
    func acknowledgePartnerPicked() async {
        let marked = (try? await dependencies.gateway.markSettingsSeen()) != nil
        await continueIntro()
        guard marked, let userID = currentUserID else { return }
        _ = try? await dependencies.cache.fetchOverview(from: dependencies.gateway, ownerUserID: userID)
        await reload()
    }

    func clearNotice() {
        notice = nil
    }
}

extension GamesViewModel {
    /// The sheet for this person's mark, shared by every board game. A phone that
    /// has never read the marks asks the server first, so a saved mark is not
    /// shown as missing.
    func makeMarkEditor() async -> BoardMarkEditorModel? {
        guard let userID = currentUserID else { return nil }
        let cache = dependencies.boardGamesCache
        var marks = await cache.document(ownerUserID: userID).marks
        if marks == nil {
            _ = try? await cache.fetchMarks(from: dependencies.boardGamesGateway, ownerUserID: userID)
            marks = await cache.document(ownerUserID: userID).marks
        }
        guard currentUserID == userID else { return nil }
        return .live(
            savedMark: marks?.mine,
            initial: BoardPieceStyle.initial(of: participants.currentName),
            userID: userID,
            dependencies: dependencies
        )
    }

    /// Follows writes to the Games cache and the pending operations. The change
    /// carries no rows, so a send queued for chat or a memory reloads too. The
    /// reload skips unchanged values, and a burst of writes while one reload runs
    /// makes one more reload.
    func observeStoreChanges() async {
        let (dirty, signal) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let forwarder = Task {
            for await change in LocalStoreChanges.changes(in: .games, .pendingOperations) {
                if change.ownerUserID == nil || change.ownerUserID == currentUserID {
                    signal.yield()
                }
            }
            signal.finish()
        }
        defer { forwarder.cancel() }
        for await _ in dirty {
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    /// The games the partner has open, in the server's order.
    nonisolated static func partnerGames(in overview: RemoteGamesOverview?) -> [GameKind] {
        (overview?.presence ?? []).filter(\.partnerPresent).map(\.kind)
    }

    /// The game the partner just opened. Both lists are freshest first. Leaving
    /// one of two open games opens nothing.
    nonisolated static func openedPartnerGame(from old: [GameKind], to new: [GameKind]) -> GameKind? {
        new.first { !old.contains($0) }
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
