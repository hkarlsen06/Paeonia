import SwiftUI

/// The picture at the top of the Mind Meld card: a short game told with word cards.
/// In the first round the two partners say SEA and SALT, one card each in their own
/// color. Then two cards land face down and flip one after the other. Both say WATER,
/// so they slide together, turn green, and a petal opens over them. It plays once when
/// the card appears. With Reduce Motion it starts finished.
struct MindMeldHubArtwork: View {
    static let height: CGFloat = 200
    private static let playDuration: TimeInterval = 4.6
    private static let playDelay: TimeInterval = 0.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlayed = false

    var body: some View {
        let shown = isPlayed || reduceMotion
        ZStack {
            background
            MindMeldHubScene(progress: shown ? 1 : 0)
                // An even pace, so each card can move on its own (see `MindMeldHubScene`).
                .animation(
                    reduceMotion ? nil : .linear(duration: Self.playDuration).delay(Self.playDelay),
                    value: isPlayed
                )
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        // The art is a picture, so it keeps its size at every text size.
        .dynamicTypeSize(.large)
        .clipped()
        .accessibilityHidden(true)
        .onAppear { isPlayed = true }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [.paeoniaSurfacePressed, .paeoniaBackgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.paeoniaPartnerOne.opacity(0.35), .clear],
                center: UnitPoint(x: 0.05, y: 0.5),
                startRadius: 0,
                endRadius: 190
            )
            RadialGradient(
                colors: [Color.paeoniaInkLavender.opacity(0.35), .clear],
                center: UnitPoint(x: 0.95, y: 0.5),
                startRadius: 0,
                endRadius: 190
            )
        }
    }
}

/// The cards. `progress` runs from 0 to 1 at an even pace, and each step takes its own
/// slice of it: the first round deals in from the sides, the second round lands face
/// down and flips, and then the two matching cards meet in the middle.
private struct MindMeldHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private typealias Timing = GameHubArtworkTiming

    private static let firstRoundSize = CGSize(width: 50, height: 62)
    private static let matchSize = CGSize(width: 62, height: 78)
    /// The middle of the band between the chips at the top and the fade at the bottom.
    private static let middleY: CGFloat = 106

    private static let sparkles = [
        GameHubSparkle(size: 13, color: .paeoniaInkGold, x: 0.29, y: 0.36),
        GameHubSparkle(size: 9, color: .paeoniaTextPrimary, x: 0.67, y: 0.26),
        GameHubSparkle(size: 11, color: .paeoniaSuccess, x: 0.69, y: 0.8),
        GameHubSparkle(size: 8, color: .paeoniaInkGold, x: 0.32, y: 0.82),
    ]

    var body: some View {
        GeometryReader { proxy in
            let middleX = proxy.size.width / 2
            ZStack {
                meetingGlow
                    .position(x: middleX, y: Self.middleY)
                firstRound(isMine: true, in: proxy.size)
                firstRound(isMine: false, in: proxy.size)
                match(isMine: true, middleX: middleX)
                match(isMine: false, middleX: middleX)
                petal
                    .position(x: middleX, y: Self.middleY - Self.matchSize.height / 2 - 14)
            }
        }
        .overlay {
            GameHubSparkleField(sparkles: Self.sparkles, progress: progress, start: 0.86)
        }
    }

    // MARK: Steps

    /// 0 to 1 while the two second-round cards slide together and turn green.
    private var meld: Double {
        Timing.ease(progress, from: 0.74, to: 0.86)
    }

    /// A round-one card. It slides in from its side, turned, and settles. Once the
    /// second round starts it fades back a little, since that round is over.
    private func firstRound(isMine: Bool, in size: CGSize) -> some View {
        let side: CGFloat = isMine ? -1 : 1
        let start = isMine ? 0.02 : 0.08
        let arrive = Timing.ease(progress, from: start, to: start + 0.16)
        let rest = CGPoint(x: size.width / 2 + side * 112, y: Self.middleY - 6)
        let offscreen = size.width / 2 + Self.firstRoundSize.width
        return MindMeldHubCardFace(
            word: isMine ? .mindMeldHubArtworkFirst : .mindMeldHubArtworkSecond,
            tint: isMine ? .paeoniaPartnerOne : .paeoniaInkLavender,
            flip: 1,
            meld: 0,
            fontSize: 11
        )
        .frame(width: Self.firstRoundSize.width, height: Self.firstRoundSize.height)
        .rotationEffect(.degrees(Double(side) * (11 + 20 * (1 - arrive))))
        .position(x: rest.x + side * offscreen * (1 - arrive), y: rest.y)
        .opacity(1 - 0.4 * Timing.ease(progress, from: 0.3, to: 0.45))
    }

    /// A round-two card. It drops in face down from below, flips, and at the end
    /// slides toward the other card.
    private func match(isMine: Bool, middleX: CGFloat) -> some View {
        let side: CGFloat = isMine ? -1 : 1
        let start = isMine ? 0.28 : 0.33
        let arrive = Timing.ease(progress, from: start, to: start + 0.14)
        let flipStart = isMine ? 0.5 : 0.6
        let flip = Timing.ease(progress, from: flipStart, to: flipStart + 0.1)
        let spread = 42 - 14 * meld
        let tilt = Double(side) * (6 - 3 * meld + 14 * (1 - arrive))
        return MindMeldHubCardFace(
            word: .mindMeldHubArtworkMatch,
            tint: isMine ? .paeoniaPartnerOne : .paeoniaInkLavender,
            flip: flip,
            meld: meld,
            fontSize: 13
        )
        .frame(width: Self.matchSize.width, height: Self.matchSize.height)
        .shadow(color: .paeoniaBackgroundSecondary.opacity(0.6), radius: 10, y: 6)
        .rotationEffect(.degrees(tilt))
        .position(x: middleX + side * spread, y: Self.middleY + 110 * (1 - arrive))
        .opacity(arrive > 0 ? 1 : 0)
    }

    /// A green light behind the two cards once they match.
    private var meetingGlow: some View {
        RadialGradient(
            colors: [Color.paeoniaSuccess.opacity(0.45), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 90
        )
        .frame(width: 180, height: 180)
        .scaleEffect(0.5 + 0.5 * meld)
        .opacity(meld)
    }

    /// The petal that opens over the match.
    private var petal: some View {
        let pop = Timing.pop(progress, from: 0.82, to: 0.92)
        return MindMeldPetalMark()
            .frame(width: 18, height: 18)
            .foregroundStyle(.paeoniaSuccess)
            .padding(PaeoniaSpacing.space8)
            .background(Color.paeoniaSuccess.opacity(0.18), in: Circle())
            .scaleEffect(max(0, pop))
            .rotationEffect(.degrees(-40 * (1 - pop)))
    }
}

/// One word card, drawn like the cards in the game: face down it shows the petal mark,
/// face up the word in capitals with a border in its owner's color. `flip` turns it
/// from face down (0) to face up (1). `meld` turns the border green.
private struct MindMeldHubCardFace: View {
    let word: LocalizedStringResource
    let tint: Color
    let flip: Double
    let meld: Double
    let fontSize: CGFloat

    private let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)

    var body: some View {
        let angle = flip * 180
        ZStack {
            back.opacity(angle < 90 ? 1 : 0)
            front
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(angle < 90 ? 0 : 1)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }

    private var back: some View {
        ZStack {
            shape.fill(.paeoniaSurfaceSecondary)
            shape
                .inset(by: PaeoniaSpacing.space4)
                .stroke(Color.paeoniaAccentPrimary.opacity(0.25), lineWidth: PaeoniaRadius.strokeHairline)
            MindMeldPetalMark()
                .frame(width: 22, height: 22)
                .foregroundStyle(Color.paeoniaAccentPrimary.opacity(0.6))
        }
        .overlay { shape.strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault) }
    }

    private var front: some View {
        let border = tint.mix(with: .paeoniaSuccess, by: meld)
        return ZStack {
            shape.fill(.paeoniaSurfacePrimary)
            // A little light from the top gives the card some depth.
            shape.fill(LinearGradient(
                colors: [Color.paeoniaTextPrimary.opacity(0.1), .clear],
                startPoint: .top,
                endPoint: .center
            ))
            Text(word)
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.paeoniaTextPrimary)
                .padding(.horizontal, PaeoniaSpacing.space4)
        }
        .overlay { shape.strokeBorder(border, lineWidth: PaeoniaRadius.strokeEmphasis) }
    }
}

#if DEBUG
#Preview {
    MindMeldHubArtwork()
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
