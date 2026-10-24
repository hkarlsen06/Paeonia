import Foundation

/// What the signed-out flow keeps on this phone between launches: the start date picked
/// before an account exists, whether anyone signed in here before, and the made-up ID the
/// unsent welcome drawing is kept under.
@MainActor
protocol WelcomeFlowStoring: AnyObject {
    var startDate: PairingStartDate? { get set }
    var hasSignedInBefore: Bool { get set }
    /// Stands in for the person and the couple in the drawing draft key, since neither
    /// exists before sign-in. Random, and never sent anywhere.
    var drawingDraftID: UUID? { get set }
}

@MainActor
final class UserDefaultsWelcomeFlowStore: WelcomeFlowStoring {
    private let defaults: UserDefaults
    private let startDateKey = "paeonia.welcome.startDate"
    private let signedInKey = "paeonia.welcome.hasSignedInBefore"
    private let drawingDraftIDKey = "paeonia.welcome.drawingDraftID"

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
}

@MainActor
final class InMemoryWelcomeFlowStore: WelcomeFlowStoring {
    var startDate: PairingStartDate?
    var hasSignedInBefore = false
    var drawingDraftID: UUID?
}
