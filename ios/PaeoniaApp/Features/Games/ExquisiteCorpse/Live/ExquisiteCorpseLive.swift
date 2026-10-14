import Foundation

/// The relay room of Exquisite corpse (`<couple>:exquisite_corpse`). The game uses
/// `WidgetLiveDrawing` for presence and roles only: it never attaches its canvas,
/// so the relay's own stroke messages never carry the part above the fold. The
/// pen glow and the strip travel as `ExquisiteCorpseLiveMessage` on a
/// `GameLiveChannel` on the same socket.
@MainActor
enum ExquisiteCorpseLive {
    static func make(coupleID: UUID) -> WidgetLiveDrawing {
        WidgetLiveDrawing(
            connection: WidgetLiveConnection(
                coupleID: coupleID,
                ticketProvider: GameLiveTicket.provider(for: .exquisiteCorpse)
            ),
            role: .present,
            presence: WidgetLivePresence(countsLatestHelloOnly: true)
        )
    }
}
