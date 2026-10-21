import Foundation
@testable import PaeoniaApp

// What each phone queued, and how it ended.
extension CorpseSimDriver {
    /// Every part a person sent either landed with the exact bytes, still waits for a reason, or was
    /// refused with a notice and is back on the canvas.
    func checkLedger(_ phone: CorpseSimPhone) async throws {
        let ledger = await phone.pending.ledger
        let stored = await phone.corpseCache.document(ownerUserID: phone.userID).notices.map(GamesNotice.init)
        let notices = phone.notices + stored
        for (position, entry) in ledger.enumerated() {
            guard let data = entry.requestData else { continue }
            switch entry.kind {
            case .exquisiteCorpseSubmitPart:
                guard let payload = try? JSONDecoder().decode(ExquisiteCorpseSubmitPartPayload.self, from: data) else {
                    continue
                }
                let later = ledger.dropFirst(position + 1)
                try checkPartEntry(entry, payload, phone: phone, notices: notices, later: later)
            case .exquisiteCorpseRevealSeen:
                try checkRevealSeenEntry(entry, data, phone: phone)
            default:
                break
            }
        }
        // Once online with nothing held, nothing may stay in the queue.
        guard phone.isAlive, phone.isForeground else { return }
        for entry in ledger where entry.outcome == .inFlight {
            throw fail("\(phone.name) \(entry.kind.rawValue) is stuck in the queue after settling")
        }
    }

    private func checkPartEntry(
        _ entry: SimPendingStore.Entry,
        _ payload: ExquisiteCorpseSubmitPartPayload,
        phone: CorpseSimPhone,
        notices: [GamesNotice],
        later: ArraySlice<SimPendingStore.Entry>
    ) throws {
        let onServer = server.parts.first { $0.id == payload.partID }
        switch entry.outcome {
        case .succeeded:
            guard let onServer, server.assets[onServer.drawingAssetID]?.data == payload.drawing.data else {
                throw fail("\(phone.name) part \(payload.partIndex) succeeded but the server holds other bytes or none")
            }
            if let strip = payload.strip, server.assets[onServer.stripAssetID ?? UUID()]?.data != strip.data {
                throw fail("\(phone.name) strip of part \(payload.partIndex) differs from the one queued")
            }
        case let .terminal(reason):
            if reason.contains("upload expired") { return }
            guard notices.contains(.exquisiteCorpsePartRejected) else {
                throw fail("\(phone.name) part \(payload.partIndex) refused without a notice: \(reason)")
            }
            let isSentAgain = later.contains { sentPartID($0) == payload.partID }
            let isOnCanvas = phone.drawingStore.draft(ownerUserID: phone.userID, roundID: payload.partID) != nil
                || phone.drawingRecord.map { $0.partID == payload.partID && $0.strokes > 0 } == true
            guard onServer != nil || isSentAgain || isOnCanvas else {
                throw fail("\(phone.name) lost part \(payload.partIndex): refused (\(reason)), not on the canvas")
            }
        case .inFlight:
            break
        }
    }

    private func checkRevealSeenEntry(_ entry: SimPendingStore.Entry, _ data: Data, phone: CorpseSimPhone) throws {
        guard let seen = try? JSONDecoder().decode(ExquisiteCorpseRevealSeenPayload.self, from: data) else { return }
        let figure = server.figures.first { $0.id == seen.figureID }
        if case .succeeded = entry.outcome, figure?.seenAt[phone.userID] == nil {
            throw fail("\(phone.name) reveal seen succeeded but the server has no time for it")
        }
    }

    private func sentPartID(_ entry: SimPendingStore.Entry) -> UUID? {
        entry.requestData.flatMap { try? JSONDecoder().decode(ExquisiteCorpseSubmitPartPayload.self, from: $0) }?.partID
    }
}
