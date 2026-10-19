import SwiftUI

/// One person's pin on the map: a round head in their color with their drawn mark
/// (or initial) on it, on a thin stem whose foot is the spot. A small shadow on the
/// map marks the foot, so the spot reads at any zoom.
struct GuessMySpotPin: View {
    let style: BoardPieceStyle
    /// The head's scale, for the reveal's build-up pulses.
    var scale: CGFloat = 1
    /// How strongly the head glows gold: 0 not at all, 1 for a spot on.
    var glow: CGFloat = 0
    /// How far above its spot the pin floats, for the drop. 0 when it stands.
    var lift: CGFloat = 0
    /// A gold ring widening from the head and fading, 0 to 1, for the verdict.
    var ring: CGFloat?
    /// Above 1, the pin stands for a cluster and shows the count on its head.
    var count = 1

    static let headSize: CGFloat = 36
    static let stemHeight: CGFloat = 22
    static let footHeight: CGFloat = 6
    static let height = headSize + stemHeight + footHeight / 2

    var body: some View {
        VStack(spacing: 0) {
            head
            Capsule()
                .fill(style.color.opacity(0.95))
                .frame(width: 3, height: Self.stemHeight)
        }
        .offset(y: -lift)
        .padding(.bottom, Self.footHeight / 2)
        .background(alignment: .bottom) {
            Ellipse()
                .fill(.black.opacity(lift > 0 ? 0.2 : 0.4))
                .frame(width: lift > 0 ? 10 : 14, height: Self.footHeight)
        }
        .frame(width: Self.headSize * 1.3, height: Self.height)
        .accessibilityHidden(true)
    }

    private var head: some View {
        ZStack {
            Circle()
                .fill(style.color)
            Circle()
                .strokeBorder(.paeoniaTextPrimary.opacity(0.85), lineWidth: 2)
            BoardMarkView(style: style, tint: .paeoniaTextInverse)
                .padding(Self.headSize * 0.2)
        }
        .frame(width: Self.headSize, height: Self.headSize)
        .shadow(
            color: glow > 0 ? Color.paeoniaInkGold.opacity(0.4 + 0.5 * glow) : .black.opacity(0.4),
            radius: glow > 0 ? 4 + 8 * glow : 3,
            y: glow > 0 ? 0 : 2
        )
        .scaleEffect(scale, anchor: .bottom)
        .overlay(alignment: .topTrailing) {
            if count > 1 {
                Text(verbatim: GuessMySpotClustering.badge(count: count))
                    .font(PaeoniaTypography.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.paeoniaTextInverse)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Color.paeoniaInkGold, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.paeoniaBackgroundSecondary, lineWidth: 1.5))
                    .offset(x: 8, y: -6)
            }
        }
        .overlay {
            if let ring {
                Circle()
                    .strokeBorder(Color.paeoniaInkGold, lineWidth: 4)
                    .frame(width: Self.headSize + 36 * ring, height: Self.headSize + 36 * ring)
                    .opacity(1 - ring)
                    .allowsHitTesting(false)
            }
        }
    }
}

#if DEBUG
#Preview {
    HStack(spacing: PaeoniaSpacing.space24) {
        GuessMySpotPin(style: BoardPieceStyle(color: .boardGameMine, mark: nil, initial: "A"))
        GuessMySpotPin(style: BoardPieceStyle(color: .boardGamePartner, mark: nil, initial: "R"), glow: 1)
        GuessMySpotPin(style: BoardPieceStyle(color: .boardGamePartner, mark: nil, initial: "R"), lift: 40)
    }
    .padding()
    .background(.paeoniaBackgroundSecondary)
}
#endif
