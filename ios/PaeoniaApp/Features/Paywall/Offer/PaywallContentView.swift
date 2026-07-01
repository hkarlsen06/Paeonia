import SwiftUI

struct PaywallContentView: View {
    let topSafeAreaInset: CGFloat
    let heroHeight: CGFloat
    let aboveFoldMinHeight: CGFloat
    @Binding var billingPeriod: PaeoniaBillingPeriod

    let headlineTitle: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let priceLine: String
    let timelineItems: [PaywallTimelineItem]
    let allowsInviteEntry: Bool
    let showsArtworkHeader: Bool
    let onRevealInvite: () -> Void

    var body: some View {
        aboveFold
            .frame(minHeight: aboveFoldMinHeight, alignment: .top)
            .background(.paeoniaSurfacePrimary)
    }

    private var aboveFold: some View {
        VStack(spacing: 0) {
            if showsArtworkHeader {
                PaywallArtworkHeader(topSafeAreaInset: topSafeAreaInset, height: heroHeight)
            } else {
                // No brand hero here (the paired paywall drops it to make room for
                // the longer copy). Reserve the status-bar area so the title still
                // clears the notch, since the scroll view ignores the top safe area.
                Color.clear
                    .frame(height: topSafeAreaInset + PaeoniaSpacing.space8)
            }

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
                .font(PaeoniaTypography.largeTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(priceLine)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, PaeoniaSpacing.space2)
        }
    }
}
