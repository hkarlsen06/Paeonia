import Foundation

/// The live drawing room of Draw & Guess. It is the widget canvas's room code on
/// a relay room of its own (`<couple>:draw_and_guess`), so a game never shares
/// the four-socket cap with Home and the canvas. The drawer joins with the
/// `drawing` role and the guesser with `watching`.
@MainActor
enum DrawAndGuessLive {
    /// Asks Convex for a 60-second relay ticket on every connect, so access is
    /// checked again after each drop and after the relay's 10-minute session
    /// limit. A nil ticket means the relay is not set up, and the game plays
    /// without live drawing.
    nonisolated static let ticketProvider: WidgetLiveConnection.TicketProvider = { _ in
        let client = try PaeoniaConvexClientProvider.shared.client()
        return try await client.mutation(
            "games:create_game_live_ticket",
            args: ["p_kind": "draw_and_guess"]
        )
    }

    static func make(
        coupleID: UUID,
        role: WidgetLivePresence.Role = .watching
    ) -> WidgetLiveDrawing {
        WidgetLiveDrawing(
            connection: WidgetLiveConnection(coupleID: coupleID, ticketProvider: ticketProvider),
            role: role
        )
    }
}
