import SwiftUI

/// The tear-off desk calendar on the Home tab countdown tile, with the day count drawn on
/// its blank page. The art scales to whatever space it gets, and the number scales with the
/// page, so the tile looks the same on a narrow phone and in the wide iPad column.
struct CountdownCalendarView: View {
    enum Face: Equatable {
        /// A blank page, for a couple that has not set the day they got together.
        case empty
        case days(Int)
        /// The event is today. The page says so instead of showing a 0.
        case today
    }

    let face: Face
    /// Changes each time the heart burst plays. Nil while it is not playing.
    var burstID: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts the heart bursts that started, so the page's word pops once as each begins
    /// and not again when the burst ends.
    @State private var popCount = 0

    /// The blank page's face as fractions of `HomeCalendar.png` (322 by 360 pixels).
    private static let page = CGRect(x: 0.030, y: 0.355, width: 0.940, height: 0.620)
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

    private func pageRect(in size: CGSize) -> CGRect {
        CGRect(
            x: Self.page.minX * size.width,
            y: Self.page.minY * size.height,
            width: Self.page.width * size.width,
            height: Self.page.height * size.height
        )
    }

    /// The text is sized from the page, not from Dynamic Type, because it is part of the
    /// picture. The tile's own text line follows Dynamic Type. Deep plum on the blush page
    /// is about 15 to 1.
    private func pageFace(in rect: CGRect) -> some View {
        ZStack {
            switch face {
            case .empty:
                EmptyView()
            case let .days(days):
                Text(days, format: .number)
                    .font(.system(size: rect.height * 0.74, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText(value: Double(days)))
                    .animation(reduceMotion ? nil : Self.countAnimation, value: days)
            case .today:
                Text(.homeMilestoneToday)
                    .font(.system(size: rect.height * 0.4, weight: .heavy, design: .rounded))
            }
        }
        .foregroundStyle(.paeoniaTextInverse)
        .lineLimit(1)
        .minimumScaleFactor(0.3)
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
