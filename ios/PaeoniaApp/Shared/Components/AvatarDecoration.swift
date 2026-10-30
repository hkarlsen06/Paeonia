import SwiftUI

nonisolated enum AvatarDecoration: String, Codable, CaseIterable, Sendable {
    case none, petals, hearts, stars

    var title: LocalizedStringResource {
        switch self {
        case .none: .avatarDecorationNone
        case .petals: .avatarDecorationPetals
        case .hearts: .avatarDecorationHearts
        case .stars: .avatarDecorationStars
        }
    }
}

nonisolated struct CoupleAvatarDecorations: Equatable, Sendable {
    var own: AvatarDecoration = .none
    var partner: AvatarDecoration = .none
}

/// Decorations sit at the sides of the portrait. The lower edge belongs to story controls.
struct AvatarDecorationArtwork: View {
    let decoration: AvatarDecoration
    let size: CGFloat

    var body: some View {
        ZStack {
            switch decoration {
            case .none:
                EmptyView()
            case .petals:
                petal(.welcomePetalLavender, scale: 0.36, x: -0.43, y: -0.20, angle: -45)
                petal(.welcomePetalPink, scale: 0.32, x: -0.32, y: -0.39, angle: -20)
                petal(.welcomePetalRose, scale: 0.31, x: 0.42, y: -0.23, angle: 65)
            case .hearts:
                heart(scale: 0.32, x: -0.40, y: -0.29, angle: -22)
                heart(scale: 0.23, x: 0.43, y: -0.22, angle: 24)
            case .stars:
                star(scale: 0.32, x: -0.42, y: -0.27, angle: -18, color: .paeoniaInkGold)
                star(scale: 0.22, x: 0.43, y: -0.27, angle: 16, color: .paeoniaInkLavender)
                star(scale: 0.15, x: 0.32, y: -0.44, angle: -12, color: .paeoniaInkGold)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func petal(_ image: ImageResource, scale: CGFloat, x: CGFloat, y: CGFloat, angle: Double) -> some View {
        Image(image)
            .resizable()
            .scaledToFit()
            .frame(width: size * scale)
            .accessibilityHidden(true)
            .rotationEffect(.degrees(angle))
            .offset(x: size * x, y: size * y)
    }

    private func heart(scale: CGFloat, x: CGFloat, y: CGFloat, angle: Double) -> some View {
        Image(.homeHeart)
            .resizable()
            .scaledToFit()
            .frame(width: size * scale)
            .accessibilityHidden(true)
            .rotationEffect(.degrees(angle))
            .offset(x: size * x, y: size * y)
    }

    private func star(scale: CGFloat, x: CGFloat, y: CGFloat, angle: Double, color: Color) -> some View {
        Image(systemName: "star.fill")
            .font(.system(size: size * scale, weight: .bold))
            .foregroundStyle(color.gradient)
            .shadow(color: .paeoniaBackgroundSecondary.opacity(0.5), radius: 1, y: 2)
            .accessibilityHidden(true)
            .rotationEffect(.degrees(angle))
            .offset(x: size * x, y: size * y)
    }
}
