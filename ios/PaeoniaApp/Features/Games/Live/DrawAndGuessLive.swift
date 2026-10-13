import Foundation

/// The live drawing room of Draw & Guess. It is the widget canvas's room code on
/// a relay room of its own (`<couple>:draw_and_guess`), so a game never shares
/// the four-socket cap with Home and the canvas. The drawer joins with the
/// `drawing` role and the guesser with `watching`. The game's own messages
/// (`DrawAndGuessLiveMessage`) share the socket through a `GameLiveChannel`.
@MainActor
enum DrawAndGuessLive {
    static func make(
        coupleID: UUID,
        role: WidgetLivePresence.Role = .watching
    ) -> WidgetLiveDrawing {
        WidgetLiveDrawing(
            connection: WidgetLiveConnection(
                coupleID: coupleID,
                ticketProvider: GameLiveTicket.provider(for: .drawAndGuess)
            ),
            role: role,
            presence: WidgetLivePresence(countsLatestHelloOnly: true)
        )
    }
}
