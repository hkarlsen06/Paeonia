import Foundation
import PencilKit
@testable import PaeoniaApp

// Scripted moves for the focused regression tests, on the same two phones and
// server the seeded runs use. Each one waits until the phones are quiet.
extension CorpseSimDriver {
    /// The phone whose turn it is on the server.
    var turnPhone: CorpseSimPhone {
        phones.first { $0.userID == server.game?.turnUser } ?? phones[0]
    }

    @discardableResult
    func require(_ phone: CorpseSimPhone, in phase: ExquisiteCorpsePhase) throws -> ExquisiteCorpseViewModel {
        guard let viewModel = phone.activeViewModel, viewModel.phase == phase else {
            throw SimFailure(message: "\(phone.name) is in \(phone.viewModel?.phase as Any), expected \(phase)")
        }
        return viewModel
    }

    /// Draws one stroke in each zone, with the pen in the room.
    func scriptDraw(_ phone: CorpseSimPhone, zones: [CorpseSimStrokes.Zone] = [.crossing, .above]) async throws {
        try require(phone, in: .drawing)
        for zone in zones {
            phone.draw(CorpseSimStrokes.stroke(seed: &random, side: phone.canvasSide, zone: zone))
        }
        await pump()
    }

    func scriptDone(_ phone: CorpseSimPhone) async throws {
        let viewModel = try require(phone, in: .drawing)
        await viewModel.finishDrawing()
        await pump()
    }

    /// The whole turn of a phone: it draws, taps Done, and everything settles.
    func scriptTurn(_ phone: CorpseSimPhone) async throws {
        try await scriptDraw(phone)
        try await scriptDone(phone)
        await settle()
    }

    /// Plays a figure to the reveal with no faults. Returns the starter, who drew the head and the legs, and the other.
    func scriptFigureToReveal() async throws -> (starter: CorpseSimPhone, other: CorpseSimPhone) {
        let starter = turnPhone
        let other = partner(of: starter)
        try await scriptTurn(starter)
        try await scriptTurn(other)
        try await scriptTurn(starter)
        return (starter, other)
    }
}
