import SwiftUI

/// A chat-style date divider: the localized day centered between two thin rules,
/// setting a gentle beat between one day's questions and the next. The date is
/// formatted in UTC so the displayed day matches the couple's local date exactly,
/// regardless of where the reader currently is.
struct DailyChallengeHistoryDateDivider: View {
    let date: Date

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            rule

            Text(date, format: dateFormat)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)
                // Long dates wrap at accessibility text sizes. The priority gives the
                // text the row's width first; the rules take what is left.
                .lineLimit(2)
                .layoutPriority(1)

            rule
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var rule: some View {
        Rectangle()
            .fill(.paeoniaSurfacePressed)
            .frame(height: PaeoniaRadius.strokeDefault)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC") ?? .gmt)
    }
}
