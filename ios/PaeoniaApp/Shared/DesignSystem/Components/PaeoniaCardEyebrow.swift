import SwiftUI

/// A small uppercase overline used at the top of cards to name a section without
/// competing with the card's main content. Keeps the Us tab cards visually
/// consistent.
struct PaeoniaCardEyebrow: View {
    private let title: LocalizedStringResource

    init(_ title: LocalizedStringResource) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(PaeoniaTypography.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(.paeoniaTextTertiary)
    }
}

#if DEBUG
#Preview {
    PaeoniaCardEyebrow(.homeDailyPromptEyebrow)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}
#endif
