import SwiftUI

/// How many times the couple has melded, in a capsule that takes no taps. Callers
/// show it only when `melds` is above zero.
struct MindMeldStatsCapsule: View {
    let melds: Int

    var body: some View {
        // An HStack, not a Label: the toolbar shows a Label as its icon only.
        HStack(spacing: PaeoniaSpacing.space4) {
            Image(systemName: "camera.macro")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
            Text(.mindMeldStatsMelds(melds))
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.paeoniaTextPrimary)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space4)
        .background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.mindMeldStatsMeldsA11Y(melds)))
        .accessibilityIdentifier("mindMeld.stats")
    }
}

/// The capsule on the first line of the content, only at accessibility text
/// sizes. At normal sizes it sits in the toolbar.
struct MindMeldStatsHeader: View {
    let melds: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize, melds > 0 {
            MindMeldStatsCapsule(melds: melds)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: PaeoniaSpacing.space16) {
        MindMeldStatsCapsule(melds: 1)
        MindMeldStatsCapsule(melds: 12)
    }
    .padding()
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
