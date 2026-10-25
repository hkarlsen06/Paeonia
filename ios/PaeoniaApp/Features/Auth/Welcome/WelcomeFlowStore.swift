import Foundation
import PencilKit

/// A doodle from the welcome widget on its way to the first drawing: PencilKit strokes
/// in the widget canvas's coordinates, a square `canvasSide` points wide.
struct WelcomeCarriedDoodle: Codable, Equatable {
    var drawingData: Data
    var canvasSide: CGFloat

    init(drawing: PKDrawing, canvasSide: CGFloat) {
        drawingData = drawing.dataRepresentation()
        self.canvasSide = canvasSide
    }

    var drawing: PKDrawing {
        (try? PKDrawing(data: drawingData)) ?? PKDrawing()
    }

    /// This doodle with `other`'s strokes on top, scaled to this one's side.
    func adding(_ other: WelcomeCarriedDoodle) -> WelcomeCarriedDoodle {
        let added = other.drawing.scaled(fromSide: other.canvasSide, toSide: canvasSide)
        return WelcomeCarriedDoodle(
            drawing: PKDrawing(strokes: drawing.strokes + added.strokes),
            canvasSide: canvasSide
        )
    }
}

/// What the signed-out flow keeps on this phone between launches: the start date picked
/// before an account exists, whether anyone signed in here before, the made-up ID the
/// unsent welcome drawing is kept under, and a welcome doodle that has not reached the
/// drawing screen yet.
@MainActor
protocol WelcomeFlowStoring: AnyObject {
    var startDate: PairingStartDate? { get set }
    var hasSignedInBefore: Bool { get set }
    /// Stands in for the person and the couple in the drawing draft key, since neither
    /// exists before sign-in. Random, and never sent anywhere.
    var drawingDraftID: UUID? { get set }
    /// Strokes drawn on the welcome widget before Start our space, until the drawing
    /// screen adds them to its draft. Never sent anywhere on their own.
    var carriedDoodle: WelcomeCarriedDoodle? { get set }
}

@MainActor
final class UserDefaultsWelcomeFlowStore: WelcomeFlowStoring {
    private let defaults: UserDefaults
    private let startDateKey = "paeonia.welcome.startDate"
    private let signedInKey = "paeonia.welcome.hasSignedInBefore"
    private let drawingDraftIDKey = "paeonia.welcome.drawingDraftID"
    private let carriedDoodleKey = "paeonia.welcome.carriedDoodle"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var startDate: PairingStartDate? {
        get { defaults.string(forKey: startDateKey).flatMap { try? PairingStartDate(rawValue: $0) } }
        set { defaults.set(newValue?.rawValue, forKey: startDateKey) }
    }

    var hasSignedInBefore: Bool {
        get { defaults.bool(forKey: signedInKey) }
        set { defaults.set(newValue, forKey: signedInKey) }
    }

    var drawingDraftID: UUID? {
        get { defaults.string(forKey: drawingDraftIDKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: drawingDraftIDKey) }
    }

    var carriedDoodle: WelcomeCarriedDoodle? {
        get {
            defaults.data(forKey: carriedDoodleKey).flatMap { data in
                try? JSONDecoder().decode(WelcomeCarriedDoodle.self, from: data)
            }
        }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: carriedDoodleKey) }
    }
}

@MainActor
final class InMemoryWelcomeFlowStore: WelcomeFlowStoring {
    var startDate: PairingStartDate?
    var hasSignedInBefore = false
    var drawingDraftID: UUID?
    var carriedDoodle: WelcomeCarriedDoodle?
}
