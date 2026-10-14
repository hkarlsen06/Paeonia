import SwiftUI

/// The small flower that closes a finished story. It scales in when `isShown`
/// turns true. When `bloomStart` is set, a burst of petals leaves from it. The
/// bloom is the Draw & Guess one, seeded by the story, so a story always
/// blooms the same way.
struct StoryChainOrnament: View {
    let isShown: Bool
    /// When the petals burst. Nil shows no burst.
    var bloomStart: Date?
    /// Makes the burst the same each time for one story, such as the story id.
    var seed = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let symbolSize: CGFloat = 44
    private static let frameHeight: CGFloat = 80
    /// The burst needs room around the flower. It draws outside the row without
    /// taking layout space.
    private static let bloomSize: CGFloat = 320

    var body: some View {
        Image(systemName: "camera.macro")
            .font(.system(size: Self.symbolSize, weight: .regular))
            .foregroundStyle(.paeoniaAccentPrimary)
            .scaleEffect(isShown ? 1 : 0.3)
            .opacity(isShown ? 1 : 0)
            .animation(reduceMotion ? nil : PaeoniaMotion.celebrationReveal, value: isShown)
            .frame(maxWidth: .infinity)
            .frame(height: Self.frameHeight)
            .background {
                if let bloomStart {
                    GamePetalBloom(start: bloomStart, seed: seed)
                        .frame(width: Self.bloomSize, height: Self.bloomSize)
                }
            }
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    StoryChainOrnament(isShown: true)
        .background(.paeoniaBackgroundSecondary)
}
#endif
