import SwiftUI

/// The picture at the top of the Story Chain card: a page of "text" drawn as soft
/// strokes in the two inks, one gold underline, and a small flower at the end of
/// the last line. The words write themselves in once when the card appears. With
/// Reduce Motion the page starts finished.
struct StoryChainHubArtwork: View {
    static let height: CGFloat = 200
    private static let writeDelay: TimeInterval = 0.3
    private static let wordStagger: TimeInterval = 0.07
    private static let pageSize = CGSize(width: 188, height: 140)
    private static let rowHeight: CGFloat = 18
    private static let strokeHeight: CGFloat = 5
    private static let wordSpacing: CGFloat = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWritten = false

    var body: some View {
        ZStack {
            background
            sparkles
            pages
                .padding(.top, PaeoniaSpacing.space24)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        // The art is a picture, so it keeps its size at every text size.
        .dynamicTypeSize(.large)
        .clipped()
        .accessibilityHidden(true)
        .onAppear {
            isWritten = true
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [.paeoniaSurfacePressed, .paeoniaBackgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [.paeoniaAccentPrimary.opacity(0.45), .clear],
                center: UnitPoint(x: 0.15, y: 0.1),
                startRadius: 0,
                endRadius: 220
            )
            RadialGradient(
                colors: [Color.paeoniaInkLavender.opacity(0.3), .clear],
                center: UnitPoint(x: 0.95, y: 0.95),
                startRadius: 0,
                endRadius: 200
            )
        }
    }

    // MARK: Sparkles

    private var sparkles: some View {
        GeometryReader { proxy in
            ForEach(Self.sparkles.indices, id: \.self) { index in
                let sparkle = Self.sparkles[index]
                Image(systemName: "sparkle")
                    .accessibilityHidden(true)
                    .font(.system(size: sparkle.size, weight: .bold))
                    .foregroundStyle(sparkle.color)
                    .position(x: proxy.size.width * sparkle.x, y: proxy.size.height * sparkle.y)
                    .opacity(isWritten ? 1 : 0)
                    .scaleEffect(isWritten ? 1 : 0.3)
                    .animation(reduceMotion ? nil : PaeoniaMotion.cardReveal.delay(Self.finishDelay), value: isWritten)
            }
        }
    }

    private struct Sparkle {
        let size: CGFloat
        let color: Color
        let x: CGFloat
        let y: CGFloat
    }

    private static let sparkles = [
        Sparkle(size: 12, color: .paeoniaInkGold, x: 0.07, y: 0.28),
        Sparkle(size: 9, color: .paeoniaTextSecondary, x: 0.12, y: 0.78),
        Sparkle(size: 14, color: .paeoniaTextPrimary, x: 0.92, y: 0.3),
        Sparkle(size: 8, color: .paeoniaInkGold, x: 0.9, y: 0.82),
    ]

    // MARK: Pages

    /// The page with the story on it, and a second page behind it.
    private var pages: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                .fill(.paeoniaSurfaceSecondary)
                .frame(width: Self.pageSize.width, height: Self.pageSize.height)
                .shadow(color: .paeoniaBackgroundSecondary.opacity(0.5), radius: 12, y: 6)
                .rotationEffect(.degrees(5))
                .offset(x: 12, y: 4)

            ZStack {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                    .fill(.paeoniaBackgroundPrimary)
                    .shadow(color: .paeoniaBackgroundSecondary.opacity(0.6), radius: 18, y: 10)
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                    .strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
                text
            }
            .frame(width: Self.pageSize.width, height: Self.pageSize.height)
            .rotationEffect(.degrees(-4))
        }
    }

    // MARK: Text

    private enum Ink {
        case mine
        case partner

        var color: Color {
            switch self {
            case .mine: .paeoniaTextPrimary
            case .partner: .paeoniaAccentPrimary
            }
        }
    }

    private struct Word {
        let width: CGFloat
        let ink: Ink
        var isDared = false
    }

    private static func mine(_ width: CGFloat) -> Word {
        Word(width: width, ink: .mine)
    }

    private static func partner(_ width: CGFloat, isDared: Bool = false) -> Word {
        Word(width: width, ink: .partner, isDared: isDared)
    }

    /// Six rows of words. The ink changes where a sentence ends, as it does on the
    /// real page, and the gold underline sits under one word.
    private static let rows: [[Word]] = [
        [mine(34), mine(22), mine(42), partner(36)],
        [partner(26), partner(40, isDared: true), partner(22), mine(34)],
        [mine(38), mine(24), partner(30), partner(38)],
        [partner(28), partner(42), mine(26), mine(34)],
        [mine(32), mine(38), mine(22), partner(36)],
        [partner(30), partner(24)],
    ]

    private static var wordCount: Int {
        rows.reduce(0) { $0 + $1.count }
    }

    /// When the flower and the sparkles pop in, after the last word.
    private static var finishDelay: TimeInterval {
        writeDelay + wordStagger * Double(wordCount) + 0.25
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.rows.indices, id: \.self) { rowIndex in
                row(rowIndex)
            }
        }
    }

    private func row(_ rowIndex: Int) -> some View {
        let words = Self.rows[rowIndex]
        let firstOrder = Self.rows[..<rowIndex].reduce(0) { $0 + $1.count }
        return HStack(spacing: Self.wordSpacing) {
            ForEach(words.indices, id: \.self) { index in
                word(words[index], order: firstOrder + index)
            }
            if rowIndex == Self.rows.count - 1 {
                flower
            }
        }
        .frame(height: Self.rowHeight, alignment: .leading)
    }

    /// A word is a rounded stroke that grows from its left end.
    private func word(_ word: Word, order: Int) -> some View {
        let delay = Self.writeDelay + Self.wordStagger * Double(order)
        let curve = PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionSlow)
        return Capsule()
            .fill(word.ink.color)
            .frame(width: word.width, height: Self.strokeHeight)
            .scaleEffect(x: isWritten ? 1 : 0.1, y: 1, anchor: .leading)
            .opacity(isWritten ? 1 : 0)
            .animation(reduceMotion ? nil : curve.delay(delay), value: isWritten)
            .overlay(alignment: .bottom) {
                if word.isDared {
                    Capsule()
                        .fill(Color.paeoniaInkGold)
                        .frame(height: 2.5)
                        .scaleEffect(x: isWritten ? 1 : 0, y: 1, anchor: .leading)
                        .offset(y: 6)
                        .animation(
                            reduceMotion ? nil : curve.delay(delay + PaeoniaMotion.motionSlow),
                            value: isWritten
                        )
                }
            }
    }

    private var flower: some View {
        Image(systemName: "camera.macro")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.paeoniaAccentSecondary)
            .scaleEffect(isWritten ? 1 : 0.2)
            .rotationEffect(.degrees(isWritten ? 0 : -30))
            .opacity(isWritten ? 1 : 0)
            .animation(reduceMotion ? nil : PaeoniaMotion.cardReveal.delay(Self.finishDelay), value: isWritten)
    }
}

#if DEBUG
#Preview {
    StoryChainHubArtwork()
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
