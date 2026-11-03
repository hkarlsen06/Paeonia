import Observation
import SwiftUI

@MainActor @Observable
final class PiccanteHubModel: GameHubModel {
    let kind = GameKind.piccante
    let game: PiccanteViewModel
    var historyLink: GameHistoryLink? { nil }
    var hasBoardMark: Bool { true }
    var state: RemotePiccanteState?
    var playStyle = GamePlayStyle.against
    private let dependencies: GamesDependencies
    private var userID: UUID?
    init(dependencies: GamesDependencies) {
        self.dependencies = dependencies
        game = PiccanteViewModel(dependencies: dependencies)
    }
    var isYourTurn: Bool { state?.unseenResult != nil || state?.game?.turnUserID == userID && userID != nil }
    func configure(participants: GameParticipants) {
        userID = participants.currentUserID
        game.configure(participants: participants)
    }
    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) { game.sync = handler }
    func reload() async {
        guard let userID else { return }
        state = await dependencies.piccanteCache.document(ownerUserID: userID).state
        playStyle = await dependencies.cache.document(ownerUserID: userID).overview?.settings?.playStyle ?? .against
    }
    func refresh() async {
        guard let userID, let loaded = try? await dependencies.piccanteGateway.loadPiccante() else { return }
        await dependencies.piccanteCache.saveState(loaded, ownerUserID: userID)
        await reload()
    }
    func card(_ context: GameHubCardContext, open: @escaping (GamesDestination) -> Void) -> AnyView? {
        AnyView(
            GameHubCardFrame(
                name: .piccanteTitle,
                status: Text(status(partner: context.partnerName)),
                actionTitle: .piccanteHubOpen, isYourTurn: isYourTurn, context: context,
                actionIdentifier: "games.hub.piccante", open: { open(.game(.piccante)) },
                artwork: { PiccanteHubArtwork() }, badge: { self.badge }, extras: { EmptyView() }))
    }
    private func status(partner: String) -> LocalizedStringResource {
        if state?.unseenResult != nil || state?.game?.phase == .finished { return .piccanteHubResult }
        if isYourTurn { return .piccanteHubTurn }
        if state?.game != nil { return .piccanteWaiting(partner) }
        return .piccanteHubNew
    }
    @ViewBuilder private var badge: some View {
        if let game = state?.game {
            Group {
                if playStyle == .against {
                    Text(.piccanteTally(game.myWins, game.partnerWins))
                } else {
                    Text(.piccanteGamesTogether(game.gamesFinished))
                }
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space4)
            .gameCapsuleStyle()
        }
    }
    func screen(for destination: GamesDestination) -> AnyView? {
        guard destination == .game(.piccante) else { return nil }
        return AnyView(PiccanteScreen(viewModel: game))
    }
}

struct PiccanteHubArtwork: View {
    var body: some View {
        GameHubArtwork(duration: 1.6) { PiccanteHubScene(progress: $0) }
    }
}

private struct PiccanteHubScene: View, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        let box = GameHubPlacement(base: CGPoint(x: 512, y: 640), width: 600, aspect: 1.447)
        ZStack {
            GameHubObject(image: .gameHubPiccanteBox, placement: box)
            GameHubBeatGlow(color: .paeoniaInkGold, center: box.point(0.80, 0.70), radius: 130, strength: progress)
        }
    }
}
