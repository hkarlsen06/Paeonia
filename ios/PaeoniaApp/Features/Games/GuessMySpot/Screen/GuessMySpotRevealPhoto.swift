import SwiftUI

/// The reveal's photo where the guess screen had it, on top or on a wide screen
/// on the left, until it slides away up or to the left.
struct GuessMySpotRevealPhoto: View {
    let image: UIImage?
    let isAway: Bool
    let isWide: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let slides = isAway && !reduceMotion
            let padding = PaeoniaSpacing.screenHorizontalPadding
            let share = GuessMySpotPhotoPane.splitShare
            GuessMySpotPhotoPane(image: image)
                .frame(
                    width: isWide ? max(0, (size.width - 2 * padding - PaeoniaSpacing.space12) * share) : nil,
                    height: max(0, isWide
                        ? size.height - PaeoniaSpacing.space8 - PaeoniaSpacing.space12
                        : size.height * share - PaeoniaSpacing.space12)
                )
                .background(.paeoniaSurfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
                .padding(.horizontal, padding)
                .padding(.top, PaeoniaSpacing.space8)
                .offset(
                    x: slides && isWide ? -size.width / 2 - 40 : 0,
                    y: slides && !isWide ? -size.height / 2 - 40 : 0
                )
                .opacity(isAway ? 0 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
