import Foundation

/// A partner's progress beyond the result still shown on this phone.
nonisolated struct GameContinuation: Equatable, Sendable {
    enum Status: Sendable {
        case waiting, picked, drawing, sentPhoto, sentDrawing, drew, wrote, started
    }

    let id: String
    let status: Status

    func title(partnerName: String) -> LocalizedStringResource {
        switch status {
        case .waiting: .gamesContinuePartnerWaiting(partnerName)
        case .picked: .gamesContinuePartnerPicked(partnerName)
        case .drawing: .gamesContinuePartnerDrawing(partnerName)
        case .sentPhoto: .gamesContinuePartnerSentPhoto(partnerName)
        case .sentDrawing: .gamesContinuePartnerSentDrawing(partnerName)
        case .drew: .gamesContinuePartnerDrew(partnerName)
        case .wrote: .gamesContinuePartnerWrote(partnerName)
        case .started: .gamesContinuePartnerStarted(partnerName)
        }
    }
}

extension GameAttention {
    func including(_ continuation: GameContinuation?) -> GameAttention {
        GameAttention(turn: turn, partnerStep: partnerStep ?? continuation?.id)
    }
}
