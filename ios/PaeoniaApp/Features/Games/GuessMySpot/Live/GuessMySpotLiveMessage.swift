import Foundation
import MapKit

/// Guess my spot's own message on its relay room: what the guesser's map shows
/// while they guess, so the sender can watch them look around. The guessing phone
/// sends it as the map moves and when the sender arrives. Nothing in it is saved.
///
/// It has no field for a pin. The guess reaches the sender through Convex, for the
/// reveal. It has no field for the real spot either, and the sending phone never
/// sends one. The real spot goes through Convex only.
nonisolated struct GuessMySpotLiveMessage: GameLiveMessage, Equatable {
    static let game = "guess_my_spot"

    /// The round being guessed. The receiver ignores any other round.
    let roundID: UUID
    let view: GuessMySpotLiveMapView
}

/// The part of the world a guess map shows, as a map rect, and whether it is the
/// satellite map.
nonisolated struct GuessMySpotLiveMapView: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let satellite: Bool

    init(_ rect: MKMapRect, satellite: Bool) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
        self.satellite = satellite
    }

    var rect: MKMapRect {
        MKMapRect(x: x, y: y, width: width, height: height)
    }
}
