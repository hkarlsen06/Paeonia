import SwiftUI

/// What the board shows while its scene loads: the dark of the room with a warm mug,
/// as the table is set. The scene fades in over the same color. With Reduce Motion the
/// mug holds still.
struct LudoLoadingView: View {
    /// The shortest time the loading view shows, and how long it takes to fade away.
    static let minimumShowTime: TimeInterval = 1.2
    static let fadeDuration: TimeInterval = 0.8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The mug and the words come in softly when the view first shows.
    @State private var isShown = false

    var body: some View {
        ZStack {
            Color(uiColor: LudoSceneStyle.color(LudoSceneStyle.roomHex))
            VStack(spacing: PaeoniaSpacing.space16) {
                Image(systemName: "cup.and.heat.waves.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(uiColor: LudoSceneStyle.color(LudoSceneStyle.myMugHex)))
                    .symbolEffect(.breathe, isActive: !reduceMotion)
                    .frame(width: 80, height: 96)
                    .accessibilityHidden(true)
                Text(.ludoLoading)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .opacity(isShown ? 1 : 0)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(reduceMotion ? nil : PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionMorph)) {
                isShown = true
            }
        }
    }
}
