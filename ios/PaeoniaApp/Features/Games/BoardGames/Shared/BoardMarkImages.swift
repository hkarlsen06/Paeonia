import Foundation
import UIKit

/// The players' drawn marks as template images, by owner. Rendering a mark is
/// slow, so a mark that has not changed keeps the image it already has.
struct BoardMarkImages {
    private var images: [UUID: (key: String, image: UIImage)] = [:]

    func image(for owner: UUID?) -> UIImage? {
        owner.flatMap { images[$0]?.image }
    }

    /// The images for `marks`, rendering only the marks that changed.
    func rendering(_ marks: RemoteBoardGameMarks?, userID: UUID, partnerID: UUID?) async -> BoardMarkImages {
        var rendered = BoardMarkImages()
        let owners: [(UUID?, RemoteBoardGameMark?)] = [(userID, marks?.mine), (partnerID, marks?.partner)]
        for case let (owner?, mark?) in owners {
            let key = "\(owner.uuidString):\(mark.updatedAt.timeIntervalSince1970)"
            if let kept = images[owner], kept.key == key {
                rendered.images[owner] = kept
                continue
            }
            guard let data = BoardMarkRenderer.data(fromBase64: mark.drawing),
                  let image = await BoardMarkRenderer.image(from: data, cacheKey: key)
            else { continue }
            rendered.images[owner] = (key, image)
        }
        return rendered
    }
}

extension BoardMarkImages {
    /// This person and their partner in the fixed couple colors, for a game without
    /// a board color choice. This person is player one.
    func coupleStyles(
        participants: GameParticipants,
        currentUserID: UUID?,
        partnerUserID: UUID?
    ) -> (mine: BoardPieceStyle, partner: BoardPieceStyle) {
        let mine = BoardPieceStyle(
            color: .boardGameMine,
            mark: image(for: currentUserID),
            initial: BoardPieceStyle.initial(of: participants.currentName),
            owner: .one
        )
        let partner = BoardPieceStyle(
            color: .boardGamePartner,
            mark: image(for: partnerUserID),
            initial: BoardPieceStyle.initial(of: participants.partnerName),
            owner: .two
        )
        return (mine, partner)
    }
}
