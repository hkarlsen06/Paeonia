import SwiftUI

/// The daily question card's scene: a sealed envelope standing on the floor. The beat
/// presses the wax seal onto the flap once when the card appears, and a warm gold glow
/// swells behind it. It follows `docs/games/hub-artwork.md`.
///
/// `sealBreak` runs from 0 to 1 when the seal breaks, once today's questions are done.
/// The seal flies off the flap and the glow flashes. The card animates it, since it is
/// not part of the beat.
struct DailyPromptHeroArtwork: View {
    let seal: DailyPromptCardArt.Seal
    let sealBreak: Double

    var body: some View {
        GameHubArtwork(duration: 1.2) { progress in
            DailyPromptHeroScene(progress: progress, sealBreak: sealBreak, seal: seal)
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
            GameHubObject(image: .homeEnvelopeSealed, placement: Self.envelope)
            GameHubBeatGlow(
                color: .paeoniaInkGold,
                center: Self.flapTip,
                radius: Self.glowRadius,
                strength: 0.7 * GameHubArtworkTiming.ease(progress, from: 0.3, to: 1) + 0.8 * sin(.pi * sealBreak)
            )
            waxSeal
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
