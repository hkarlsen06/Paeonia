import SwiftUI

/// The square surface every drawing sits on. It has the ink color of the widget
/// canvas, so a saved drawing looks like a widget drawing.
struct GameSquare<Content: View>: View {
    let side: CGFloat
    /// 1 while playing, 0.8 on the result.
    var scale: CGFloat = 1
    /// The soft glow behind the square on the reveal, 0 for none.
    var glow: Double = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: side, height: side)
            .background(.paeoniaBackgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                    .strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
                    .allowsHitTesting(false)
            }
            .background {
                RadialGradient(
                    colors: [.paeoniaAccentPrimary.opacity(glow), .clear],
                    center: .center,
                    startRadius: side * 0.2,
                    endRadius: side * 0.85
                )
                .frame(width: side * 1.7, height: side * 1.7)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .scaleEffect(scale)
            .frame(width: side * scale, height: side * scale)
    }
}
