import Foundation
import Observation
import PencilKit

/// One creature from "Our creatures": the folded paper opens once at the pace the
/// reveal uses, without the bloom, with the credits and this person's own star.
/// "Play again" starts it over.
@MainActor
@Observable
final class ExquisiteCorpseHistoryDetailViewModel {
    enum DrawingState: Equatable {
        case loading
        case failed
        case ready
    }

    let figure: RemoteExquisiteCorpseFigure
    let stars: GameStars
    /// Opens the folds one by one. It makes no haptics here.
    let timeline: ExquisiteCorpseRevealTimeline
    /// Replays the strokes of each part.
    let player: ExquisiteCorpseFigurePlayer
    private(set) var drawingState: DrawingState = .loading
    /// The figure with the drawings that have loaded. The credits show before then.
    private(set) var content: ExquisiteCorpseRevealContent

    @ObservationIgnored private let participants: GameParticipants
    @ObservationIgnored private let drawings: GameHistoryDrawings
    /// Reduce Motion: the whole creature shows at once, and "Play again" replays
    /// the strokes without the folds.
    @ObservationIgnored private var showsAtOnce = false

    init(
        figure: RemoteExquisiteCorpseFigure,
        participants: GameParticipants,
        stars: GameStars,
        drawings: GameHistoryDrawings,
        timeline: ExquisiteCorpseRevealTimeline? = nil,
        player: ExquisiteCorpseFigurePlayer? = nil
    ) {
        // Built here and not as default arguments, which are not main actor code.
        let timeline = timeline ?? ExquisiteCorpseRevealTimeline(haptics: .silent)
        let player = player ?? ExquisiteCorpseFigurePlayer(selection: {})
        self.figure = figure
        self.participants = participants
        self.stars = stars
        self.drawings = drawings
        self.timeline = timeline
        self.player = player
        content = Self.content(of: figure, drawings: [:], participants: participants)
        player.onPartFinished = { [timeline] part in
            timeline.partReplayFinished(part)
        }
    }

    // MARK: - What the screen shows

    var isStarred: Bool {
        stars.isStarred(figure.id)
    }

    /// The date the creature was finished, as the screen says it: "Oct 12".
    var dateText: String {
        (figure.finishedAt ?? figure.createdAt).formatted(date: .abbreviated, time: .omitted)
    }

    func toggleStar() async {
        await stars.toggle(id: figure.id)
    }

    // MARK: - Loading

    /// Loads the three drawings and opens the paper once. With `showsAtOnce`
    /// (Reduce Motion) the finished creature shows and "Play again" replays it.
    func load(showsAtOnce: Bool) async {
        guard drawingState != .ready else { return }
        self.showsAtOnce = showsAtOnce
        drawingState = .loading
        let files = await fetchFiles()
        guard !Task.isCancelled else { return }
        var loaded: [ExquisiteCorpsePartKind: PKDrawing] = [:]
        for (kind, data) in files {
            if let drawing = try? PKDrawing(data: data) {
                loaded[kind] = drawing
            }
        }
        guard loaded.count == ExquisiteCorpsePartKind.allCases.count else {
            drawingState = .failed
            return
        }
        content = Self.content(of: figure, drawings: loaded, participants: participants)
        player.load(loaded)
        if showsAtOnce {
            player.finish()
        }
        drawingState = .ready
        timeline.begin(reduceMotion: showsAtOnce)
    }

    func retryLoading(showsAtOnce: Bool) async {
        await load(showsAtOnce: showsAtOnce)
    }

    /// The `.pkdrawing` bytes of each part the phone has or can download. A part
    /// that fails is left out.
    private func fetchFiles() async -> [ExquisiteCorpsePartKind: Data] {
        let wanted = ExquisiteCorpsePartKind.allCases.compactMap { kind in
            figure.part(at: kind.rawValue)?.drawingMediaAssetID.map { (kind, $0) }
        }
        let drawings = drawings
        return await withTaskGroup(of: (ExquisiteCorpsePartKind, Data?).self) { group in
            for (kind, assetID) in wanted {
                group.addTask { (kind, await drawings.data(for: assetID)) }
            }
            var files: [ExquisiteCorpsePartKind: Data] = [:]
            for await (kind, data) in group {
                files[kind] = data
            }
            return files
        }
    }

    // MARK: - Replay

    /// The timeline has opened a part's fold, so its strokes start.
    func timelineStageChanged(to stage: ExquisiteCorpseRevealTimeline.Stage) {
        if case let .playing(part) = stage {
            player.start(part)
        }
    }

    /// "Play again".
    func replay() {
        guard drawingState == .ready else { return }
        if showsAtOnce {
            player.playInSequence()
        } else {
            player.reset()
            timeline.reset()
            timeline.begin(reduceMotion: false)
        }
    }

    /// A tap, and "Show the whole figure" for VoiceOver.
    func showWholeFigure() {
        guard drawingState == .ready else { return }
        timeline.skip()
        player.finish()
    }

    /// Ends the run when the screen goes away.
    func stop() {
        timeline.stop()
        player.finish()
    }

    // MARK: - Content

    private static func content(
        of figure: RemoteExquisiteCorpseFigure,
        drawings: [ExquisiteCorpsePartKind: PKDrawing],
        participants: GameParticipants
    ) -> ExquisiteCorpseRevealContent {
        let (me, partner) = participants.players
        let parts = ExquisiteCorpsePartKind.allCases.compactMap { kind -> ExquisiteCorpseRevealContent.Part? in
            guard let remote = figure.part(at: kind.rawValue) else { return nil }
            let isMine = remote.drawerUserID == participants.currentUserID
            return ExquisiteCorpseRevealContent.Part(
                kind: kind,
                drawing: drawings[kind],
                drawerIsMe: isMine,
                drawer: isMine ? me : partner,
                idea: remote.idea?.text
            )
        }
        return ExquisiteCorpseRevealContent(
            figureID: figure.id,
            number: figure.number,
            parts: parts,
            partnerName: participants.partnerName,
            // The partner who drew the body starts the next creature.
            nextIsMine: figure.starterUserID != participants.currentUserID
        )
    }
}

extension ExquisiteCorpseRevealTimeline.Haptics {
    /// No haptics. "Our creatures" opens a creature quietly.
    static let silent = Self(selection: {}, foldLanded: { _ in }, answerRevealed: {})
}
