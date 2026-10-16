#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

struct TheirTimeLockScreenView: View {
    @Environment(\.widgetFamily) private var family

    let entry: LockScreenEntry

    private var clock: LockScreenPartnerClock? {
        LockScreenPartnerClock(timeZoneID: entry.snapshot?.partner?.timeZoneID)
    }

    var body: some View {
        if let clock, let partner = entry.snapshot?.partner {
            if family == .accessoryRectangular {
                rectangular(clock, partner: partner)
            } else {
                TheirTimeClockFace(clock: clock, date: entry.date)
            }
        } else {
            LockScreenUnavailableView(symbol: "clock", title: .widgetLockScreenTheirTimeName)
        }
    }

    private func rectangular(_ clock: LockScreenPartnerClock, partner: LockScreenSnapshot.Partner) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label { Text(firstName(partner.displayName)) } icon: { Image(systemName: "clock") }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .widgetAccentable()
            Text(clock.timeText(at: entry.date))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(offsetText(clock.offset(at: entry.date, from: .autoupdatingCurrent)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func firstName(_ displayName: String?) -> String {
        let name = displayName?.split(separator: " ").first.map(String.init)
        return name ?? String(localized: .widgetLockScreenPartnerFallback)
    }

    private func offsetText(_ offset: LockScreenPartnerClock.Offset) -> String {
        switch offset {
        case .same:
            return String(localized: .widgetLockScreenTheirTimeSame)
        case let .ahead(minutes):
            return minutes.isMultiple(of: 60)
                ? String(localized: .widgetLockScreenTheirTimeAheadHours(minutes / 60))
                : String(localized: .widgetLockScreenTheirTimeAhead(duration(minutes)))
        case let .behind(minutes):
            return minutes.isMultiple(of: 60)
                ? String(localized: .widgetLockScreenTheirTimeBehindHours(minutes / 60))
                : String(localized: .widgetLockScreenTheirTimeBehind(duration(minutes)))
        }
    }

    /// "3 hours, 30 minutes" in the person's language, for gaps that are not whole hours.
    private func duration(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}

/// An analog clock showing the partner's time, with a sun or moon under the center.
struct TheirTimeClockFace: View {
    let clock: LockScreenPartnerClock
    let date: Date

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            ClockTicksShape()
                .stroke(.primary.opacity(0.7), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .padding(4)
            ClockHandShape(degrees: clock.hourHandDegrees(at: date), lengthFraction: 0.5)
                .stroke(.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .padding(4)
                .widgetAccentable()
            ClockHandShape(degrees: clock.minuteHandDegrees(at: date), lengthFraction: 0.78)
                .stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .padding(4)
                .widgetAccentable()
            Image(systemName: clock.isDaytime(at: date) ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 9))
                .offset(y: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(clock.timeText(at: date)))
    }
}

/// Twelve ticks, longer at 12, 3, 6 and 9.
private struct ClockTicksShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for tick in 0..<12 {
            let angle = Double(tick) * .pi / 6
            let inner = radius * (tick.isMultiple(of: 3) ? 0.78 : 0.88)
            path.move(to: point(center: center, radius: inner, angle: angle))
            path.addLine(to: point(center: center, radius: radius, angle: angle))
        }
        return path
    }
}

private struct ClockHandShape: Shape {
    /// Clockwise from 12 o'clock.
    let degrees: Double
    /// Hand length as a fraction of the face radius.
    let lengthFraction: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * lengthFraction
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(center: center, radius: radius, angle: degrees * .pi / 180))
        return path
    }
}

/// A point `radius` away from `center`, `angle` radians clockwise from 12 o'clock.
private func point(center: CGPoint, radius: Double, angle: Double) -> CGPoint {
    CGPoint(x: center.x + sin(angle) * radius, y: center.y - cos(angle) * radius)
}
#endif
