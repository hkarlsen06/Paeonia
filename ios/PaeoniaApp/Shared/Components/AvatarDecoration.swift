import SwiftUI

nonisolated enum AvatarDecoration: String, Codable, CaseIterable, Sendable {
    case none, peony, ribbon, moon, candy
    case mischief, flame, rose, woodland, cosy, silver, halloween, christmas, winter

    /// The largest frame extends this far beyond the photo. Reserve room for nearby content.
    static let maximumOutset: CGFloat = 0.28

    var title: LocalizedStringResource {
        switch self {
        case .none: .avatarDecorationNone
        case .peony: .avatarDecorationPeony
        case .ribbon: .avatarDecorationRibbon
        case .moon: .avatarDecorationMoon
        case .candy: .avatarDecorationCandy
        case .mischief: .avatarDecorationMischief
        case .flame: .avatarDecorationFlame
        case .rose: .avatarDecorationRose
        case .woodland: .avatarDecorationWoodland
        case .cosy: .avatarDecorationCosy
        case .silver: .avatarDecorationSilver
        case .halloween: .avatarDecorationHalloween
        case .christmas: .avatarDecorationChristmas
        case .winter: .avatarDecorationWinter
        }
    }

    @MainActor var image: ImageResource? {
        switch self {
        case .none: nil
        case .peony: .avatarFramePeony
        case .ribbon: .avatarFrameRibbon
        case .moon: .avatarFrameMoon
        case .candy: .avatarFrameCandy
        case .mischief: .avatarFrameMischief
        case .flame: .avatarFrameFlame
        case .rose: .avatarFrameRose
        case .woodland: .avatarFrameWoodland
        case .cosy: .avatarFrameCosy
        case .silver: .avatarFrameSilver
        case .halloween: .avatarFrameHalloween
        case .christmas: .avatarFrameChristmas
        case .winter: .avatarFrameWinter
        }
    }

    /// Align the middle of each frame's band with the photo edge, covering its border.
    /// Scales use measured band diameters in the centered 1024px canvases.
    var artworkScale: CGFloat {
        switch self {
        case .none: 1
        case .peony: 1_024 / 770
        case .ribbon: 1_024 / 760
        case .moon: 1_024 / 740
        case .candy: 1_024 / 740
        case .mischief: 1.59441
        case .flame: 1.66248
        case .rose: 1.67140
        case .woodland: 1.62090
        case .cosy: 1.72128
        case .silver: 1.51091
        case .halloween: 1.63189
        case .christmas: 1.66898
        case .winter: 1.62578
        }
    }

    /// Rounded up from the centered artwork's measured opaque bounds.
    var outset: CGFloat {
        switch self {
        case .none: 0
        case .peony, .ribbon, .moon, .candy: 0.12
        case .mischief: 0.12
        case .flame: 0.28
        case .rose: 0.20
        case .woodland: 0.15
        case .cosy: 0.16
        case .silver: 0.04
        case .halloween: 0.15
        case .christmas: 0.23
        case .winter: 0.13
        }
    }

    func noteClearance(photoSize: CGFloat) -> CGFloat {
        photoSize * outset
    }
}

nonisolated struct CoupleAvatarDecorations: Equatable, Sendable {
    var own: AvatarDecoration = .none
    var partner: AvatarDecoration = .none
}

/// The frame overlaps the photo's border. Story controls are drawn separately above it.
struct AvatarDecorationArtwork: View {
    let decoration: AvatarDecoration
    let size: CGFloat

    var body: some View {
        if let image = decoration.image {
            Image(image)
                .resizable()
                .accessibilityHidden(true)
                .scaledToFit()
                .frame(width: size * decoration.artworkScale, height: size * decoration.artworkScale)
                .frame(width: size, height: size)
                .allowsHitTesting(false)
        }
    }
}
