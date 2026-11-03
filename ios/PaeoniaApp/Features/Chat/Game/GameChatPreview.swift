import SwiftUI

/// Only public boards and already revealed content belong in a chat thumbnail.
nonisolated enum GameChatPreview: Equatable, Sendable {
    case board(GameChatBoardPreview)
    case drawing(UUID)
    case creature([UUID])
    case photo(UUID)
    case words(String, String)
    case story(String)
    case scale(spot: Int, guess: Int)

    /// The side of the square a preview is drawn in (`GameChatPreviewContent`), in points.
    static let side: CGFloat = 240
}

nonisolated struct GameChatBoardPreview: Equatable, Sendable {
    let kind: GameKind
    let moves: [Int]
    let me: BoardPlayer
    var colors = LudoColorPair.standard
}

struct GameChatPreviewLoader {
    let dependencies: GamesDependencies

    func load(for kind: GameKind, userID: UUID) async -> GameChatPreview? {
        switch kind {
        case .connectFour, .dotsAndBoxes, .ultimateTicTacToe, .ludo:
            return await loadBoard(for: kind, userID: userID)
        case .drawAndGuess:
            let state = await dependencies.cache.document(ownerUserID: userID).state
            let rounds = [state?.currentRound].compactMap { $0 } + (state?.recentRounds ?? [])
            return rounds.first { $0.drawingSubmittedAt != nil }?.drawingMediaAssetID.map(GameChatPreview.drawing)
        case .exquisiteCorpse:
            let state = await dependencies.exquisiteCorpseCache.document(ownerUserID: userID).state
            let figures = [state?.currentFigure].compactMap { $0 } + (state?.recentFigures ?? [])
            guard let figure = figures.first(where: \.isFinished) else { return nil }
            return .creature(figure.parts.sorted { $0.partIndex < $1.partIndex }.compactMap(\.drawingMediaAssetID))
        case .guessMySpot:
            let state = await dependencies.guessMySpotCache.document(ownerUserID: userID).state
            return (state?.currentRound ?? state?.previousRound).map { .photo($0.photoMediaAssetID) }
        case .mindMeld:
            return await loadWords(userID: userID)
        case .storyChain:
            return await loadStory(userID: userID)
        case .consensio:
            return await loadScale(userID: userID)
        }
    }

    private func loadStory(userID: UUID) async -> GameChatPreview? {
        let state = await dependencies.storyChainCache.document(ownerUserID: userID).state
        guard let story = state?.currentStory ?? state?.previousStory else { return nil }
        return .story(
            ([story.title, story.openingText].compactMap { $0 } + story.lines.map(\.text)).joined(separator: "\n"))
    }

    private func loadWords(userID: UUID) async -> GameChatPreview? {
        let document = await dependencies.mindMeldCache.document(ownerUserID: userID)
        let state = document.state
        let rounds =
            Array((state?.current?.rounds ?? []).reversed()) + Array((state?.previous?.rounds ?? []).reversed())
        guard let round = rounds.first(where: { $0.state == .revealed }),
            let mine = round.myWord, let theirs = round.partnerWord
        else {
            guard let round = document.history?.games.first?.rounds.last else { return nil }
            return .words(round.myWord, round.partnerWord)
        }
        return .words(mine, theirs)
    }

    private func loadScale(userID: UUID) async -> GameChatPreview? {
        let state = await dependencies.consensioCache.document(ownerUserID: userID).state
        guard
            let round = [state?.currentRound, state?.previousRound].compactMap({ $0 }).first(where: {
                $0.guessedAt != nil
            }),
            let spot = round.spot, let guess = round.guess
        else { return nil }
        return .scale(spot: spot, guess: guess)
    }

    private func loadBoard(for kind: GameKind, userID: UUID) async -> GameChatPreview? {
        let document = await dependencies.boardGamesCache.document(ownerUserID: userID)
        guard let state = document.state, let game = state.game(kind), let partnerID = state.partnerUserID,
            let pending = await BoardGamePendingWork.load(from: dependencies.pendingOperationStore, ownerUserID: userID)
        else { return nil }
        switch kind {
        case .connectFour:
            return boardPreview(game, pending: pending, userID: userID, partnerID: partnerID, as: ConnectFourBoard.self)
        case .dotsAndBoxes:
            return boardPreview(
                game, pending: pending, userID: userID, partnerID: partnerID, as: DotsAndBoxesBoard.self)
        case .ultimateTicTacToe:
            return boardPreview(
                game, pending: pending, userID: userID, partnerID: partnerID, as: UltimateTicTacToeBoard.self)
        default: return boardPreview(game, pending: pending, userID: userID, partnerID: partnerID, as: LudoBoard.self)
        }
    }

    private func boardPreview<Board: BoardGameRules>(
        _ game: RemoteBoardGame, pending: [BoardGamePendingAction], userID: UUID, partnerID: UUID, as: Board.Type
    ) -> GameChatPreview? {
        guard
            let snapshot = BoardGameResolver.resolve(
                game, pending: pending, userID: userID, partnerID: partnerID, as: Board.self)
        else { return nil }
        if snapshot.moves.isEmpty, let previous = snapshot.previous {
            return .board(
                .init(
                    kind: game.kind, moves: previous.moves, me: previous.firstUserID == userID ? .one : .two,
                    colors: .init(mine: snapshot.myColor ?? .pink, partner: snapshot.partnerColor ?? .lavender)))
        }
        return .board(
            .init(
                kind: game.kind, moves: snapshot.moves, me: snapshot.player(for: userID),
                colors: .init(mine: snapshot.myColor ?? .pink, partner: snapshot.partnerColor ?? .lavender)))
    }
}
