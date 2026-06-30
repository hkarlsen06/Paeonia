import SwiftUI

struct PaywallContentView: View {
    let topSafeAreaInset: CGFloat
    let heroHeight: CGFloat
    let aboveFoldMinHeight: CGFloat
    @Binding var billingPeriod: PaeoniaBillingPeriod

    let headlineTitle: LocalizedStringResource
    let priceLine: String
    let timelineItems: [PaywallTimelineItem]
    let allowsInviteEntry: Bool
    let onRevealInvite: () -> Void

    var body: some View {
        aboveFold
            .frame(minHeight: aboveFoldMinHeight, alignment: .top)
            .background(.paeoniaSurfacePrimary)
    }

    private var aboveFold: some View {
        VStack(spacing: 0) {
            PaywallArtworkHeader(topSafeAreaInset: topSafeAreaInset, height: heroHeight)

            VStack(alignment: .leading, spacing: 0) {
                headlineBlock

                PaywallBillingSelector(billingPeriod: $billingPeriod)
                    .padding(.top, PaeoniaSpacing.space20)

                Spacer(minLength: PaeoniaSpacing.space32)

                PaywallTimelineView(items: timelineItems)

                Spacer(minLength: PaeoniaSpacing.space24)

                if allowsInviteEntry {
                    PaywallScrollCue(onTap: onRevealInvite)
                        .padding(.bottom, PaeoniaSpacing.space20)
                }
            }
            .padding(.horizontal, PaeoniaSpacing.space20)
            .padding(.top, PaeoniaSpacing.space24)
            .frame(maxWidth: 430)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var headlineBlock: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(headlineTitle)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(.paywallSubtitle)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(priceLine)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, PaeoniaSpacing.space2)
        }
    }
}
