import SwiftUI

/// Shares the avatar's spring so the line ends at its moving perimeter.
nonisolated struct PairingCelebrationLandingConnector: Shape {
    let heartCenter: CGPoint
    var avatarCenter: CGPoint
    var avatarScale: CGFloat
    let heartRadius: CGFloat
    let avatarRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(avatarCenter.x, avatarCenter.y), avatarScale) }
        set {
            avatarCenter = CGPoint(x: newValue.first.first, y: newValue.first.second)
            avatarScale = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let deltaX = avatarCenter.x - heartCenter.x
        let deltaY = avatarCenter.y - heartCenter.y
        let distance = hypot(deltaX, deltaY)
        let avatarRadius = avatarRadius * avatarScale

        // There is no exposed line while the avatar covers the central heart.
        guard distance > heartRadius + avatarRadius else { return Path() }

        var path = Path()
        path.move(to: CGPoint(
            x: heartCenter.x + deltaX / distance * heartRadius,
            y: heartCenter.y + deltaY / distance * heartRadius
        ))
        path.addLine(to: CGPoint(
            x: avatarCenter.x - deltaX / distance * avatarRadius,
            y: avatarCenter.y - deltaY / distance * avatarRadius
        ))
        return path
    }
}
