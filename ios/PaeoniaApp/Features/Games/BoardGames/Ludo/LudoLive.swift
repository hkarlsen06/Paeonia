import Foundation

/// A roll on its way to the partner's phone. The roller sends it the moment the
/// die starts to tumble, so the partner's die tumbles at the same time and lands
/// on the same face. The tumble is scripted, so it looks the same on both phones.
/// The move that carries the roll still goes through Convex, which stays the
/// record. Nothing in this message is saved.
nonisolated struct LudoLiveMessage: GameLiveMessage, Equatable {
    static let game = "ludo"

    /// The position the roll is for and the face it lands on. The receiver
    /// ignores it until its board reaches that position.
    let roll: LudoSavedRoll
}

/// Ludo's relay room (`<couple>:ludo`), used only for live rolls. Both phones
/// join with the `present` role.
@MainActor
enum LudoLive {
    static func make(coupleID: UUID) -> WidgetLiveDrawing {
        WidgetLiveDrawing(
            connection: WidgetLiveConnection(
                coupleID: coupleID,
                ticketProvider: GameLiveTicket.provider(for: .ludo)
            ),
            role: .present,
            presence: WidgetLivePresence(countsLatestHelloOnly: true)
        )
    }
}

/// Joins one Ludo screen's die to the relay room while the screen is open. My
/// rolls go out as they start, and again when my partner opens the game in the
/// middle of my turn. My partner's rolls go to the roll model.
@MainActor
final class LudoLiveLink {
    private let room: WidgetLiveDrawing
    private let channel: GameLiveChannel<LudoLiveMessage>
    private weak var roll: LudoRollModel?

    init(room: WidgetLiveDrawing, roll: LudoRollModel) {
        self.room = room
        self.roll = roll
        let channel = GameLiveChannel<LudoLiveMessage>(connection: room.connection)
        self.channel = channel
        channel.onMessage = { [weak roll] message in
            roll?.receivePartnerRoll(message.roll)
        }
        room.onPartnerArrived = { [weak roll] in
            guard let current = roll?.ownRoll else { return }
            channel.send(LudoLiveMessage(roll: current))
        }
        roll.announce = { channel.send(LudoLiveMessage(roll: $0)) }
        room.start()
    }

    func stop() {
        roll?.announce = nil
        room.onPartnerArrived = nil
        room.stop()
    }
}
