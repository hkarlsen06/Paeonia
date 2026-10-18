import SwiftUI

/// The small flower that closes a finished story. It scales in when `isShown`
/// turns true.
struct StoryChainOrnament: View {
    let isShown: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let symbolSize: CGFloat = 44
    private static let frameHeight: CGFloat = 80

    var body: some View {
        Image(systemName: "camera.macro")
            .font(.system(size: Self.symbolSize, weight: .regular))
            .foregroundStyle(.paeoniaAccentPrimary)
            .scaleEffect(isShown ? 1 : 0.3)
            .opacity(isShown ? 1 : 0)
            .animation(reduceMotion ? nil : PaeoniaMotion.celebrationReveal, value: isShown)
            .frame(maxWidth: .infinity)
            .frame(height: Self.frameHeight)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    StoryChainOrnament(isShown: true)
        .background(.paeoniaBackgroundSecondary)
}
#endif
