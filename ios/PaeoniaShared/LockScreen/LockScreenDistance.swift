import Foundation

/// The "Distance apart" widget. Under a kilometer the couple counts as together.
nonisolated enum LockScreenDistance: Equatable, Sendable {
    /// The partner or this person has location sharing off, or no position yet.
    case unavailable
    case together
    case apart(meters: Double)

    static let togetherBelowMeters = 1_000.0

    init(_ distance: LockScreenSnapshot.Distance?) {
        guard let meters = distance?.meters, meters.isFinite, meters >= 0 else {
            self = .unavailable
            return
        }
        self = meters < Self.togetherBelowMeters ? .together : .apart(meters: meters)
    }

    /// A distance split into the number and the unit, for the round widget, and
    /// joined, for the one-line widget. US and UK locales get miles.
    struct Formatted: Equatable, Sendable {
        let number: String
        let unit: String
        let combined: String
    }

    static func text(meters: Double, locale: Locale) -> Formatted {
        let unit: UnitLength = switch locale.measurementSystem {
        case .us, .uk: .miles
        default: .kilometers
        }
        let measurement = Measurement(value: meters, unit: UnitLength.meters).converted(to: unit)

        let formatter = MeasurementFormatter()
        formatter.locale = locale
        // `.short` drops the space before the unit ("7 716km"), so the sentence
        // uses `.medium`. The round widget keeps the short unit ("mi", not "miles").
        formatter.unitStyle = .medium
        formatter.unitOptions = .providedUnit
        // Whole numbers for long distances so "7,750" fits a small widget.
        formatter.numberFormatter.maximumFractionDigits = measurement.value < 100 ? 1 : 0

        let combined = formatter.string(from: measurement)
        formatter.unitStyle = .short
        return Formatted(
            number: formatter.numberFormatter.string(from: NSNumber(value: measurement.value)) ?? "",
            unit: formatter.string(from: unit),
            combined: combined
        )
    }
}
