import SwiftUI

/// The daily question card's scene: a sealed envelope standing on the floor. The beat
/// presses the wax seal onto the flap once when the card appears, and a warm gold glow
/// swells behind it. It follows `docs/games/hub-artwork.md`.
///
/// `sealBreak` runs from 0 to 1 when the seal breaks, once today's question is answered.
/// The seal flies off the flap and the glow flashes. Then `opening` folds the flap back
/// and a letter rises in the pocket. The card animates both, since they are not part of
/// the beat.
struct DailyPromptHeroArtwork: View {
    let seal: DailyPromptCardArt.Seal
    let sealBreak: Double
    var opening = DailyPromptEnvelopeOpening.closed

    var body: some View {
        GameHubArtwork(duration: 1.2) { progress in
            DailyPromptHeroScene(progress: progress, sealBreak: sealBreak, seal: seal, opening: opening)
        }
    }
}

/// How far the daily card's envelope has opened.
enum DailyPromptEnvelopeOpening {
    case closed
    /// The flap is folding back.
    case flapOpening
    /// The flap is behind the letter, which has risen in the pocket.
    case letterOut
}

/// The daily card's envelope with a letter in its pocket, `width` wide. The open flap
/// reaches above its frame.
struct DailyPromptEnvelope: View {
    let width: CGFloat
    let opening: DailyPromptEnvelopeOpening

    var body: some View {
        PaeoniaEnvelope(width: width, isOpen: opening != .closed, isFlapBehind: opening == .letterOut) {
            PaeoniaEnvelopeLetter(width: width * 0.55, height: width * 0.45)
                .offset(y: opening == .letterOut ? -width * 0.06 : width * 0.07)
        }
    }
}

/// In the canvas's pixels. The envelope is centered, its lower edge at 640. The seal sits
/// on the tip of the closed flap, 0.495 across and 0.614 down the picture, measured on
/// the asset's pixels (445 and 306 of 900 by 498).
private struct DailyPromptHeroScene: View, Animatable {
    var progress: Double
    var sealBreak: Double
    let seal: DailyPromptCardArt.Seal
    let opening: DailyPromptEnvelopeOpening

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, sealBreak) }
        set {
            progress = newValue.first
            sealBreak = newValue.second
        }
    }

    private static let envelope = GameHubPlacement(base: CGPoint(x: 512, y: 640), width: 560, aspect: 1.807)
    private static let flapTip = envelope.point(0.495, 0.614)
    private static let sealWidth: CGFloat = 150
    private static let glowRadius: CGFloat = 240

    var body: some View {
        ZStack {
            envelope
            GameHubBeatGlow(
                color: .paeoniaInkGold,
                center: Self.flapTip,
                radius: Self.glowRadius,
                strength: 0.7 * GameHubArtworkTiming.ease(progress, from: 0.3, to: 1) + 0.8 * sin(.pi * sealBreak)
            )
            waxSeal
        }
    }

    /// The envelope standing on the floor, with a soft shadow under it like the hub's
    /// other objects (`GameHubObject`).
    private var envelope: some View {
        let placement = Self.envelope
        return ZStack {
            Ellipse()
                .fill(Color.paeoniaBackgroundSecondary.opacity(0.4))
                .frame(width: placement.width * 0.8, height: max(18, placement.height * 0.07))
                .blur(radius: 10)
                .position(x: placement.base.x, y: placement.base.y - 4)
            DailyPromptEnvelope(width: placement.width, opening: opening)
                .position(x: placement.base.x, y: placement.base.y - placement.height / 2)
        }
    }

    /// Drops in from larger, presses a little too deep, and settles. When it breaks it
    /// lifts, turns and fades.
    private var waxSeal: some View {
        let press = GameHubArtworkTiming.pop(progress, from: 0.05, to: 0.35)
        let appear = GameHubArtworkTiming.ease(progress, from: 0.05, to: 0.15)
        return Image(sealImage)
            .resizable()
            .accessibilityHidden(true)
            .scaledToFit()
            .frame(width: Self.sealWidth)
            .shadow(color: .paeoniaBackgroundSecondary.opacity(0.4 * min(1, max(0, press))), radius: 8, y: 5)
            .scaleEffect((1.55 - 0.55 * press) * (1 + 0.4 * sealBreak))
            .rotationEffect(.degrees(24 * sealBreak))
            .offset(y: -70 * sealBreak)
            .opacity(appear * (1 - sealBreak))
            .position(Self.flapTip)
    }

    private var sealImage: ImageResource {
        switch seal {
        case .pink: .homeWaxSealPink
        case .lavender: .homeWaxSealLavender
        }
    }
}

#if DEBUG
#Preview {
    DailyPromptHeroArtwork(seal: .pink, sealBreak: 0)
        .frame(width: 335, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
