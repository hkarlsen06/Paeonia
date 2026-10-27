import Foundation
import MapKit

/// Guess my spot's own messages on its relay room. Nothing in them is saved.
///
/// No message has a field for a pin. The guess reaches the sender through Convex,
/// for the reveal. No message has a field for the real spot either: the preview is
/// a few pixels re-encoded on the phone, without the photo's metadata. The real
/// spot goes through Convex only.
nonisolated enum GuessMySpotLiveMessage: GameLiveMessage, Equatable {
    static let game = "guess_my_spot"

    /// What the guesser's map shows while they guess, so the sender can watch them
    /// look around. The guessing phone sends it as the map moves and when the sender
    /// arrives. The receiver ignores any round but the one it waits on.
    case guessMap(roundID: UUID, view: GuessMySpotLiveMapView)
    /// The photo the sender picked and is checking, as a JPEG of at most
    /// `GuessMySpotPhotoPreview.maxPixelSize` pixels, so the guesser sees it coming,
    /// blurred. `roundID` is the round the photo will make. The sending phone sends
    /// it on each pick and when the guesser arrives.
    case photoPreview(roundID: UUID, jpeg: Data)
    /// The sender went back to the picker without sending.
    case photoPreviewCleared
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
