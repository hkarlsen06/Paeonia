import Foundation
@testable import PaeoniaApp

/// Deterministic Exquisite corpse state for the tests. The viewer is `me`. Figure
/// 1 is started by the partner, so the partner draws its head and legs and `me`
/// draws the body. Figure 2 is started by `me`, and so on.
enum ExquisiteCorpseFixture {
    static let me = UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID()
    static let partner = UUID(uuidString: "22222222-2222-4222-8222-222222222222") ?? UUID()
    static let couple = UUID(uuidString: "33333333-3333-4333-8333-333333333333") ?? UUID()
    static let gameID = UUID(uuidString: "44444444-4444-4444-8444-444444444444") ?? UUID()
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static let resolver = ExquisiteCorpseResolver(userID: me)

    static func figureID(_ number: Int) -> UUID {
        ExquisiteCorpseIDs.figure(gameID: gameID, number: number)
    }

    /// The partner starts the odd figures and `me` the even ones.
    static func starter(ofFigure number: Int) -> UUID {
        number.isMultiple(of: 2) ? me : partner
    }

    /// The head and the legs belong to the starter and the body to the other one.
    static func drawer(ofFigure number: Int, partIndex: Int) -> UUID {
        let starter = starter(ofFigure: number)
        return partIndex == 1 ? (starter == me ? partner : me) : starter
    }

    static func partID(figure number: Int, partIndex: Int) -> UUID {
        ExquisiteCorpseIDs.part(
            gameID: gameID,
            figureNumber: number,
            partIndex: partIndex,
            drawerID: drawer(ofFigure: number, partIndex: partIndex)
        )
    }

    static func idea(_ text: String = "a robot") -> RemoteExquisiteCorpseIdea {
        RemoteExquisiteCorpseIdea(id: "idea-\(text.replacingOccurrences(of: " ", with: "-"))", text: text)
    }

    static func part(
        figure number: Int,
        index: Int,
        idea: RemoteExquisiteCorpseIdea? = nil
    ) -> RemoteExquisiteCorpsePart {
        RemoteExquisiteCorpsePart(
            id: partID(figure: number, partIndex: index),
            partIndex: index,
            drawerUserID: drawer(ofFigure: number, partIndex: index),
            createdAt: now.addingTimeInterval(Double(index)),
            stripMediaAssetID: index < 2 ? assetID(figure: number, index: index, isStrip: true) : nil,
            drawingMediaAssetID: assetID(figure: number, index: index, isStrip: false),
            idea: idea
        )
    }

    /// The same id for the same file every time, so two fixtures of one state are equal.
    static func assetID(figure number: Int, index: Int, isStrip: Bool) -> UUID {
        let seed = UInt8(truncatingIfNeeded: number * 8 + index * 2 + (isStrip ? 1 : 0))
        return UUID(uuid: (0xA5, seed, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, seed))
    }

    /// A figure with its first `parts` parts. A finished figure has all three.
    static func figure(
        _ number: Int,
        parts: Int = 3,
        revealSeen: Bool = false,
        starred: Bool = false
    ) -> RemoteExquisiteCorpseFigure {
        RemoteExquisiteCorpseFigure(
            id: figureID(number),
            number: number,
            starterUserID: starter(ofFigure: number),
            createdAt: now,
            finishedAt: parts == 3 ? now.addingTimeInterval(3) : nil,
            myRevealSeenAt: revealSeen ? now.addingTimeInterval(10) : nil,
            starredByMe: starred,
            parts: (0..<parts).map { part(figure: number, index: $0) }
        )
    }

    /// The game when the next part of figure `number` is `partIndex` and `turn` draws it.
    static func game(figure number: Int, partIndex: Int, turn: UUID) -> RemoteExquisiteCorpseGame {
        RemoteExquisiteCorpseGame(
            id: gameID,
            turnUserID: turn,
            turnStartedAt: now,
            figureID: partIndex == 0 ? nil : figureID(number),
            figureNumber: number,
            partIndex: partIndex,
            figuresFinished: number - 1,
            version: 1,
            createdAt: now,
            updatedAt: now
        )
    }

    static func state(
        game: RemoteExquisiteCorpseGame?,
        current: RemoteExquisiteCorpseFigure? = nil,
        recent: [RemoteExquisiteCorpseFigure] = [],
        ideas: [RemoteExquisiteCorpseIdea] = []
    ) -> RemoteExquisiteCorpseState {
        RemoteExquisiteCorpseState(
            userID: me,
            partnerUserID: partner,
            coupleID: couple,
            dataEpoch: "",
            game: game,
            currentFigure: current,
            recentFigures: recent,
            ideas: ideas
        )
    }

    /// A part of `me` that waits on the phone. The ids match the server's next part of `figure`.
    static func queuedPart(
        figure number: Int,
        partIndex: Int,
        idea: RemoteExquisiteCorpseIdea? = nil
    ) -> ExquisiteCorpseSubmitPartPayload {
        func upload() -> ExquisiteCorpseQueuedUpload {
            ExquisiteCorpseQueuedUpload(
                data: Data([1, 2, 3]),
                reserveOperation: SyncClientOperation(clientID: UUID(), clientSequence: 1),
                finalizeOperation: SyncClientOperation(clientID: UUID(), clientSequence: 2)
            )
        }
        return ExquisiteCorpseSubmitPartPayload(
            gameID: gameID,
            figureID: figureID(number),
            partID: ExquisiteCorpseIDs.part(gameID: gameID, figureNumber: number, partIndex: partIndex, drawerID: me),
            partIndex: partIndex,
            coupleID: couple,
            drawing: upload(),
            strip: partIndex < 2 ? upload() : nil,
            idea: idea,
            createdAt: now.addingTimeInterval(100)
        )
    }

    static func pending(
        parts: [ExquisiteCorpseSubmitPartPayload] = [],
        revealsSeen: [UUID] = [],
        stars: [(figure: UUID, starred: Bool)] = []
    ) -> ExquisiteCorpsePendingWork {
        var work = ExquisiteCorpsePendingWork()
        work.parts = parts
        work.revealsSeen = revealsSeen.map { ExquisiteCorpseRevealSeenPayload(figureID: $0, createdAt: now) }
        work.stars = stars.map { ExquisiteCorpseStarPayload(figureID: $0.figure, starred: $0.starred, createdAt: now) }
        return work
    }
}
