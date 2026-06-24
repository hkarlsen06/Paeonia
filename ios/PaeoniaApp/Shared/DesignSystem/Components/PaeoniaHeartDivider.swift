import SwiftUI

/// A small ornament — a heart flanked by two short, fading rules — used to set a
/// gentle, intimate beat between a title and its supporting line. Shared across
/// the sign-in and paywall screens so the brand reads the same in both.
struct PaeoniaHeartDivider: View {
    /// Overall width of the ornament. The rules fill whatever is left after the
    /// heart, so a wider value yields longer rules.
    var width: CGFloat = 96

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            rule(fadingToward: .leading)

            Image(systemName: "heart.fill")
                .font(.system(size: 10))
                .foregroundStyle(.paeoniaAccentPrimary)

            rule(fadingToward: .trailing)
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }

    private func rule(fadingToward edge: UnitPoint) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.paeoniaAccentPrimary, .clear],
                    startPoint: edge == .leading ? .trailing : .leading,
                    endPoint: edge
                )
            )
            .frame(height: 1)
    }
}

#Preview {
    PaeoniaHeartDivider()
        .padding()
        .background(.paeoniaSurfacePrimary)
        .preferredColorScheme(.dark)
}
