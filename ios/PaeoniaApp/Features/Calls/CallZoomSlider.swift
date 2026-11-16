import SwiftUI

/// Zooms the back camera during a video call, counted as the Camera app counts it. The slider
/// moves on a log scale, so 0.5× to 1× takes as much room as 1× to 2×.
struct CallZoomSlider: View {
    let zoom: CallCameraZoom
    let setZoom: (Double) -> Void
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            // As wide as the widest value, so the slider never moves while the number changes.
            Text(verbatim: Self.label(8.8))
                .hidden()
                .overlay { Text(verbatim: Self.label(zoom.factor)).callTurned() }
                .font(PaeoniaTypography.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Slider(
                value: Binding(get: { log(zoom.factor) }, set: { setZoom(exp($0)) }),
                in: log(zoom.range.lowerBound)...log(zoom.range.upperBound),
                onEditingChanged: onEditingChanged
            )
            .tint(.white)
            .accessibilityLabel(Text(.callsZoom))
            .accessibilityValue(Text(verbatim: Self.label(zoom.factor)))
            .accessibilityIdentifier("calls.zoom")
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space8)
        .frame(maxWidth: 300)
        .glassEffect(.regular, in: Capsule())
        // Flipping to the front camera mid-drag removes the slider before the drag can end.
        .onDisappear { onEditingChanged(false) }
    }

    private static func label(_ factor: Double) -> String {
        factor.formatted(.number.precision(.fractionLength(0...1))) + "×"
    }
}
