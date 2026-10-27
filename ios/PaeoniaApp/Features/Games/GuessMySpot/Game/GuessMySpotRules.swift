import Foundation

/// How close a guess came, as the reveal says it.
nonisolated enum GuessMySpotVerdict: Equatable, Sendable {
    /// Up to 1 km off.
    case spotOn
    /// Up to 25 km off.
    case soClose
    /// Up to 300 km off.
    case close
    /// More than 300 km off.
    case far
}

/// The rules the phone and the server share (`backend/convex/lib/guessMySpot.ts`).
nonisolated enum GuessMySpotRules {
    static let maxPoints = 5_000
    /// A guess this close scores all the points.
    static let fullPointsMeters = 25.0
    /// A guess this far off scores none.
    static let zeroPointsMeters = 20_000_000.0
    static let earthRadiusMeters = 6_371_008.8
    static let placeNameMaxLength = 120

    /// `round(5000 × log10(20,000 km / d) / log10(20,000 km / 25 m))`, with `d` held between 25 m and 20,000 km.
    static func points(distanceMeters: Int) -> Int {
        let distance = min(zeroPointsMeters, max(fullPointsMeters, Double(distanceMeters)))
        let share = log10(zeroPointsMeters / distance) / log10(zeroPointsMeters / fullPointsMeters)
        return Int((Double(maxPoints) * share).rounded())
    }

    static func verdict(distanceMeters: Int) -> GuessMySpotVerdict {
        switch distanceMeters {
        case ...1_000: .spotOn
        case ...25_000: .soClose
        case ...300_000: .close
        default: .far
        }
    }

    /// The great-circle distance in whole metres (haversine), as the server computes it.
    static func distanceMeters(_ from: GuessMySpotCoordinate, _ to: GuessMySpotCoordinate) -> Int {
        let lat1 = radians(from.latitude)
        let lat2 = radians(to.latitude)
        let dLat = lat2 - lat1
        let dLon = radians(to.longitude - from.longitude)
        let haversine = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return Int((2 * earthRadiusMeters * asin(min(1, sqrt(haversine)))).rounded())
    }

    /// The point `fraction` of the way from `from` to `to` along the great circle.
    static func intermediate(
        from: GuessMySpotCoordinate,
        to: GuessMySpotCoordinate,
        fraction: Double
    ) -> GuessMySpotCoordinate {
        let lat1 = radians(from.latitude), lon1 = radians(from.longitude)
        let lat2 = radians(to.latitude), lon2 = radians(to.longitude)
        let angle = Double(distanceMeters(from, to)) / earthRadiusMeters
        guard angle > 1e-9, sin(angle) > 1e-9 else { return fraction < 0.5 ? from : to }
        let fromWeight = sin((1 - fraction) * angle) / sin(angle)
        let toWeight = sin(fraction * angle) / sin(angle)
        let pointX = fromWeight * cos(lat1) * cos(lon1) + toWeight * cos(lat2) * cos(lon2)
        let pointY = fromWeight * cos(lat1) * sin(lon1) + toWeight * cos(lat2) * sin(lon2)
        let pointZ = fromWeight * sin(lat1) + toWeight * sin(lat2)
        return GuessMySpotCoordinate(
            latitude: degrees(atan2(pointZ, sqrt(pointX * pointX + pointY * pointY))),
            longitude: degrees(atan2(pointY, pointX))
        )
    }

    /// True for a spot the server takes.
    static func isValid(_ coordinate: GuessMySpotCoordinate) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite
            && (-90...90).contains(coordinate.latitude) && (-180...180).contains(coordinate.longitude)
    }

    /// Trims, collapses whitespace and caps the length, or nil when nothing is left.
    static func placeName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        // The server counts Unicode code points.
        let scalars = collapsed.unicodeScalars.prefix(placeNameMaxLength)
        return String(String.UnicodeScalarView(scalars))
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}

/// Distances and points as the screens write them. Distances are metric in both
/// languages: whole metres under 10 m, tens of metres under 1 km, one decimal of a
/// kilometre under 10 km, and whole kilometres above.
nonisolated enum GuessMySpotText {
    static func distance(_ meters: Int, locale: Locale = .current) -> String {
        if meters < 10 {
            return format(Double(max(0, meters)), .meters, digits: 0, locale: locale)
        }
        if meters < 995 {
            return format(Double((meters + 5) / 10 * 10), .meters, digits: 0, locale: locale)
        }
        let kilometers = Double(meters) / 1_000
        let digits = kilometers < 9.95 ? 1 : 0
        return format(kilometers, .kilometers, digits: digits, locale: locale)
    }

    private static func format(_ value: Double, _ unit: UnitLength, digits: Int, locale: Locale) -> String {
        let style = Measurement<UnitLength>.FormatStyle(
            width: .abbreviated,
            locale: locale,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(digits))
        )
        return Measurement(value: value, unit: unit).formatted(style)
    }

    static func number(_ value: Int, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale))
    }

    /// `YYYY-MM-DD` as a long date, such as "June 12, 2024", or nil for anything else.
    static func takenOn(_ day: String?, locale: Locale = .current) -> String? {
        guard let date = GuessMySpotDay.date(from: day) else { return nil }
        var style = Date.FormatStyle(date: .long, time: .omitted).locale(locale)
        style.timeZone = .gmt
        return date.formatted(style)
    }
}

/// The photo's day as the server keeps it: `YYYY-MM-DD`, with no time zone.
nonisolated enum GuessMySpotDay {
    static func date(from day: String?) -> Date? {
        guard let day, day.count == 10 else { return nil }
        return try? Date(day, strategy: Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
    }

    static func string(year: Int, month: Int, day: Int) -> String? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard components.isValidDate(in: calendar) else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
