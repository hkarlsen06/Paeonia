import SwiftUI

/// A small card over the middle of the board that says how to zoom and turn it. The
/// board shows it until this phone has zoomed or turned it once, so it shows the
/// first times Ludo opens and then never again. It never takes a touch.
struct LudoGestureHints: View {
    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: "line.diagonal.trianglehead.up.right.left.down")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(.ludoGestureHintZoom)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
        // The moves are for sight. VoiceOver reaches the pieces through its own layer.
        .accessibilityHidden(true)
        .transition(.opacity)
    }
}
