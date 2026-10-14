import Foundation

/// The live room of Story Chain, on a relay room of its own
/// (`<couple>:story_chain`). The screen uses `WidgetLiveDrawing` only for
/// presence and the socket. There is no canvas. The game's own messages
/// (`StoryChainLiveMessage`) share the socket through a `GameLiveChannel`.
@MainActor
enum StoryChainLive {
    static func make(coupleID: UUID) -> WidgetLiveDrawing {
        WidgetLiveDrawing(
            connection: WidgetLiveConnection(
                coupleID: coupleID,
                ticketProvider: GameLiveTicket.provider(for: .storyChain)
            ),
            role: .present,
            presence: WidgetLivePresence(countsLatestHelloOnly: true)
        )
    }
}
