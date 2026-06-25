import SwiftUI

struct PairedHomeView: View {
    let currentDisplayName: String?
    let partnerDisplayName: String?

    var body: some View {
        VStack(spacing: 0) {
            PaeoniaBrandLockup(
                wordmarkSize: 36,
                taglineSize: 17,
                taglineColor: .paeoniaTextSecondary
            )
            .frame(maxWidth: .infinity)

            if let pairNames {
                Text(verbatim: pairNames)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .padding(.top, PaeoniaSpacing.space20)
            }

            Spacer(minLength: PaeoniaSpacing.space32)

            PaeoniaEmptyStateView(
                title: .rootEmptyTitle,
                message: .rootEmptyMessage,
                systemImage: "heart.circle.fill"
            )
            .frame(maxWidth: 360)

            Spacer(minLength: PaeoniaSpacing.space32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pairNames: String? {
        guard let currentDisplayName = currentDisplayName?.trimmedNonEmpty,
              let partnerDisplayName = partnerDisplayName?.trimmedNonEmpty else {
            return nil
        }

        return "\(currentDisplayName) + \(partnerDisplayName)"
    }
}

#Preview {
    PairedHomeView(
        currentDisplayName: "Hjalmar",
        partnerDisplayName: "Oda"
    )
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .padding(.top, PaeoniaSpacing.screenTopSpacing)
    .padding(.bottom, PaeoniaSpacing.space16)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
