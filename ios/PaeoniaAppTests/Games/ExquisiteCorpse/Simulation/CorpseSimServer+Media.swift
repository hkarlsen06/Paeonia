import Foundation
@testable import PaeoniaApp

extension CorpseSimServer {
    // MARK: - Uploads and downloads

    /// Reserve, upload and finalize in one step. The same reservation gives the
    /// same asset, unless the orphan sweep deleted it.
    func upload(
        user: UUID,
        data: Data,
        parent: GameUploadParent,
        reserveOperation: SyncClientOperation
    ) throws -> UUID {
        guard parent.kind == "exquisite_corpse_part",
              ["exquisite_corpse_drawing", "exquisite_corpse_strip"].contains(parent.purpose)
        else {
            throw fail("23514", "exquisite corpse upload contract is invalid")
        }
        guard game?.id == parent.gameID else { throw noAccess() }
        if let existing = uploadsByReservation[reserveOperation.id] {
            guard assets[existing]?.queuedForDelete == false else {
                throw fail("42501", "media upload reservation is not available")
            }
            return existing
        }
        let id = UUID()
        assets[id] = Asset(id: id, owner: user, partID: parent.id, purpose: parent.purpose, data: data, createdAt: now)
        uploadsByReservation[reserveOperation.id] = id
        return id
    }

    /// The weekly sweep: an upload no part used within seven days is deleted.
    func sweepOrphanedUploads() -> Int {
        var swept = 0
        for (id, asset) in assets where !asset.queuedForDelete && now.timeIntervalSince(asset.createdAt) > 7 * 86_400 {
            if !parts.contains(where: { $0.drawingAssetID == id || $0.stripAssetID == id }) {
                assets[id]?.queuedForDelete = true
                swept += 1
            }
        }
        return swept
    }

    /// `canReadCorpseAsset`: a strip is readable by the couple once a part uses
    /// it. A full drawing is readable by its drawer, and by the partner once the figure is finished.
    func download(user: UUID, assetID: UUID) throws -> Data {
        let asset = assets[assetID]
        let part = parts.first { $0.drawingAssetID == assetID || $0.stripAssetID == assetID }
        let isFinished = part.flatMap { part in figures.first { $0.id == part.figureID }?.finishedAt } != nil
        let isStrip = asset?.purpose == "exquisite_corpse_strip"
        let allowed = asset != nil && asset?.queuedForDelete == false && part != nil
            && (isStrip || isFinished || part?.drawer == user)
        downloads.append(Download(
            user: user,
            assetID: assetID,
            purpose: asset?.purpose,
            drawer: part?.drawer,
            figureFinished: isFinished,
            allowed: allowed
        ))
        guard allowed, let asset else { throw GameDrawingTransferError.downloadUnavailable }
        return asset.data
    }

    /// `assertCorpseAssetUsable`.
    func requireUsable(_ assetID: UUID, user: UUID, partID: UUID, purpose: String) throws {
        let label = purpose == "exquisite_corpse_drawing" ? "drawing" : "strip"
        guard let asset = assets[assetID], asset.owner == user, asset.partID == partID, asset.purpose == purpose,
              !asset.queuedForDelete
        else {
            throw fail("23514", "exquisite corpse \(label) asset is not usable")
        }
        let isTaken = parts.contains { label == "drawing" ? $0.drawingAssetID == assetID : $0.stripAssetID == assetID }
        if isTaken {
            throw uniqueViolation("exquisite_corpse_parts_\(label)_media_asset_id_unique_idx")
        }
    }
}
