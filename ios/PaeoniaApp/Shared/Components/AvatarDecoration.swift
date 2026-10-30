import SwiftUI

nonisolated enum AvatarDecoration: String, Codable, CaseIterable, Sendable {
    case none, peony, ribbon, moon, candy

    /// The largest frame extends this far beyond the photo. Reserve room for nearby content.
    static let maximumOutset: CGFloat = 0.22

    var title: LocalizedStringResource {
        switch self {
        case .none: .avatarDecorationNone
        case .peony: .avatarDecorationPeony
        case .ribbon: .avatarDecorationRibbon
        case .moon: .avatarDecorationMoon
        case .candy: .avatarDecorationCandy
        }
    }

    @MainActor var image: ImageResource? {
        switch self {
        case .none: nil
        case .peony: .avatarFramePeony
        case .ribbon: .avatarFrameRibbon
        case .moon: .avatarFrameMoon
        case .candy: .avatarFrameCandy
        }
    }

    /// Measured inner rims in the untrimmed 1024px exports. Petals may overlap the photo's edge.
    var artworkScale: CGFloat {
        switch self {
        case .none: 1
        case .peony: 1_024 / 680
        case .ribbon: 1_024 / 660
        case .moon: 1_024 / 666
        case .candy: 1_024 / 674
        }
    }

    func noteClearance(photoSize: CGFloat) -> CGFloat {
        self == .none ? 0 : photoSize * Self.maximumOutset
    }
}

nonisolated struct CoupleAvatarDecorations: Equatable, Sendable {
    var own: AvatarDecoration = .none
    var partner: AvatarDecoration = .none
}

/// The frame meets the photo's outline. Story controls are drawn separately above it.
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
