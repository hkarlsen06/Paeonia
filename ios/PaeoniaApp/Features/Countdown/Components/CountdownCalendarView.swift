import SwiftUI

/// The tear-off desk calendar on the Us tab countdown tile, with the day count and "days"
/// drawn on its blank page. The text scales with the page and follows Dynamic Type.
struct CountdownCalendarView: View {
    enum Face: Equatable {
        case loading
        /// A question mark, for a couple with no date to count down to yet.
        case empty
        case days(Int)
        /// The event is today. The page says so instead of showing a 0.
        case today
    }

    let face: Face
    /// Changes each time the heart burst plays. Nil while it is not playing.
    var burstID: Int?

    @ScaledMetric(relativeTo: .largeTitle) private var textScale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts the heart bursts that started, so the page's word pops once as each begins
    /// and not again when the burst ends.
    @State private var popCount = 0

    /// The blank page's face as fractions of `HomeCalendar.png` (450 by 447 pixels).
    private static let page = CGRect(x: 0.040, y: 0.270, width: 0.920, height: 0.680)
    /// How much of the page's width the number may use. The rest is margin.
    private static let numberWidthShare: CGFloat = 0.88
    /// One roll of the digits when the count changes: the first showing after launch and the
    /// midnight rollover.
    private static let countAnimation = Animation.easeOut(duration: 0.6)

    var body: some View {
        Image(.homeCalendar)
            .resizable()
            .accessibilityHidden(true)
            .scaledToFit()
            .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 4)
            .overlay {
                GeometryReader { proxy in
                    pageFace(in: pageRect(in: proxy.size))
                }
            }
            .accessibilityHidden(true)
            .onChange(of: burstID) { _, burstID in
                if burstID != nil, !reduceMotion { popCount += 1 }
            }
    }

    /// The count with "days" under it.
    private func daysFace(_ days: Int, in rect: CGRect) -> some View {
        VStack(spacing: -rect.height * 0.06) {
            Text(days, format: .number)
                .font(.system(size: rect.height * 0.48 * textScale, weight: .heavy, design: .rounded))
                .contentTransition(.numericText(value: Double(days)))
                .animation(reduceMotion ? nil : Self.countAnimation, value: days)
            Text(days == 1 ? .homeMilestonePageDaysOne : .homeMilestonePageDays)
                .font(.system(size: rect.height * 0.15 * textScale, weight: .bold, design: .rounded))
        }
    }

    private func pageRect(in size: CGSize) -> CGRect {
        CGRect(
            x: Self.page.minX * size.width,
            y: Self.page.minY * size.height,
            width: Self.page.width * size.width,
            height: Self.page.height * size.height
        )
    }

    private func pageFace(in rect: CGRect) -> some View {
        ZStack {
            switch face {
            case .loading:
                Color.clear
            case .empty:
                Text(verbatim: "?")
                    .font(.system(size: rect.height * 0.58 * textScale, weight: .heavy, design: .rounded))
            case let .days(days):
                daysFace(days, in: rect)
            case .today:
                Text(.homeMilestoneToday)
                    .font(.system(size: rect.height * 0.28 * textScale, weight: .heavy))
            }
        }
        // The page stays blank while the count loads, then the number comes into focus as
        // it rolls up.
        .paeoniaLoadingReveal(face == .loading)
        .foregroundStyle(.paeoniaTextInverse)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.25)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: popCount) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(1.18, duration: 0.18, spring: .snappy)
            SpringKeyframe(1, duration: 0.5, spring: .bouncy)
        }
        .frame(width: rect.width * Self.numberWidthShare, height: rect.height)
        // Behind the word, so the hearts come out from under it.
        .background {
            if let burstID {
                MilestoneHeartBurst(unit: rect.height)
                    .id(burstID)
                    .transition(.opacity)
            }
        }
        .position(x: rect.midX, y: rect.midY)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: PaeoniaSpacing.space16) {
        CountdownCalendarView(face: .days(104))
        CountdownCalendarView(face: .today, burstID: 1)
        CountdownCalendarView(face: .empty)
    }
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundPrimary)
}
#endif
