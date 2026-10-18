import SwiftUI

/// One person's pin on the line: a round head in their color with their drawn
/// mark (or initial) on it, on a thin stem that stands on the line. The stem
/// lifts the head above the finger, so a dragging finger never covers it.
struct ConsensioMarker: View {
    let style: BoardPieceStyle
    /// A finger holds it: the head lifts and grows a little.
    var isLifted = false
    /// The head's extra scale for the reveal's build-up pulses.
    var pulseScale: CGFloat = 1
    /// How strongly the head glows gold on the reveal: 0 not at all, 0.5 for a
    /// close guess, 1 for a spot on.
    var glow: CGFloat = 0
    /// 1 on the screens where a pin is moved, larger on the reveal.
    var size: CGFloat = 1
    /// Degrees the pin leans, around the foot of its stem. Two pins that stand
    /// close lean apart until their heads touch.
    var tilt: Double = 0

    static let headSize: CGFloat = 36
    static let stemHeight: CGFloat = 26
    static let height = headSize + stemHeight

    private var headSide: CGFloat { Self.headSize * size }

    var body: some View {
        VStack(spacing: 0) {
            head
            stem
        }
        .frame(width: headSide, height: Self.height * size)
        .rotationEffect(.degrees(tilt), anchor: .bottom)
        .accessibilityHidden(true)
    }

    private var head: some View {
        ZStack {
            Circle()
                .fill(style.color)
            Circle()
                .strokeBorder(.paeoniaTextPrimary.opacity(0.85), lineWidth: 2)
            BoardMarkView(style: style, tint: .paeoniaTextInverse)
                .padding(headSide * 0.2)
        }
        .frame(width: headSide, height: headSide)
        .shadow(
            color: glow > 0 ? Color.paeoniaInkGold.opacity(0.4 + 0.4 * glow) : .black.opacity(0.35),
            radius: glow > 0 ? 4 + 6 * glow : 3,
            y: glow > 0 ? 0 : 2
        )
        .scaleEffect((isLifted ? 1.1 : 1) * pulseScale, anchor: .bottom)
        .offset(y: isLifted ? -6 * size : 0)
    }

    private var stem: some View {
        Capsule()
            .fill(style.color.opacity(0.9))
            .frame(width: 3 * size, height: Self.stemHeight * size)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: PaeoniaSpacing.space24) {
        ConsensioMarker(style: BoardPieceStyle(color: .boardGameMine, mark: nil, initial: "A"))
        ConsensioMarker(style: BoardPieceStyle(color: .boardGamePartner, mark: nil, initial: "R"), isLifted: true)
        ConsensioMarker(style: BoardPieceStyle(color: .boardGamePartner, mark: nil, initial: "R"), glow: 1)
    }
    .padding()
    .background(.paeoniaBackgroundSecondary)
}
#endif
