import SwiftUI

/// The pinned bottom of the paywall: the button that buys, the billing terms right
/// under it, and, for someone not paired yet, a way to join a partner instead.
struct PaywallBottomCTAView: View {
    let title: LocalizedStringResource
    /// Billing terms (price, period, trial) shown right under the button that buys.
    let caption: String?
    let isEnabled: Bool
    let isBusy: Bool
    /// The purchase or the join went through and the next screen is on its way.
    /// The button says so and stays put instead of offering to buy again.
    let isDone: Bool
    let isJoiningPartner: Bool
    let onPrimaryAction: () -> Void
    let onHaveInviteCode: (() -> Void)?

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            primaryCTA
            captionLine
            inviteButton
        }
        .padding(.top, PaeoniaSpacing.space16)
        .padding(.bottom, onHaveInviteCode == nil ? PaeoniaSpacing.space8 : 0)
        .background(barBackground)
    }

    private var looksEnabled: Bool {
        isEnabled || isDone
    }

    private var primaryCTA: some View {
        Button(action: onPrimaryAction) {
            ZStack {
                if isDone {
                    Label {
                        Text(.paywallCtaDone)
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else if isBusy {
                    ProgressView()
                        .tint(.paeoniaTextInverse)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                } else {
                    Text(title)
                        .transition(.opacity)
                }
            }
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .foregroundStyle(looksEnabled ? .paeoniaTextInverse : .paeoniaTextTertiary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(primaryButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isDone)
        .animation(PaeoniaMotion.stateChange, value: isBusy)
        .animation(PaeoniaMotion.cardReveal, value: isDone)
        .accessibilityLabel(Text(isDone ? .paywallCtaDone : title))
        .accessibilityIdentifier("paywall.primaryAction")
        // A soft tap when the App Store work starts. Success has its own haptic
        // on the paywall, and a cancel should not feel like anything happened.
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isBusy) { _, isNowBusy in
            isNowBusy
        }
    }

    /// While prices load, a placeholder holds the terms' place, so the bar doesn't
    /// grow under the plans when they arrive.
    @ViewBuilder
    private var captionLine: some View {
        if let caption = caption ?? (isBusy ? Self.placeholderCaption : nil) {
            Text(caption)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .redacted(reason: self.caption == nil ? .placeholder : [])
        }
    }

    private static var placeholderCaption: String {
        String(localized: .paywallDisclosureSubscription("000 kr \(String(localized: .paywallPeriodMonthly))"))
    }

    @ViewBuilder
    private var inviteButton: some View {
        if let onHaveInviteCode {
            Button(action: onHaveInviteCode) {
                HStack(spacing: PaeoniaSpacing.space8) {
                    if isJoiningPartner {
                        ProgressView()
                            .tint(.paeoniaAccentPrimary)
                            .accessibilityHidden(true)
                    }
                    Text(.paywallInviteEntry)
                        .foregroundStyle(.paeoniaAccentPrimary)
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .disabled(isBusy || isDone || isJoiningPartner)
            .accessibilityIdentifier("paywall.haveInviteCode")
        }
    }

    private var primaryButtonBackground: LinearGradient {
        // Disabled uses an opaque, recessed fill (never translucent) so the
        // button reads as a solid disabled control rather than washing out.
        let enabledColors = [
            Color.paeoniaAccentPrimary,
            Color.paeoniaAccentSecondary,
        ]
        let disabledColors = [
            Color.paeoniaSurfaceSecondary,
            Color.paeoniaSurfaceSecondary,
        ]

        return LinearGradient(
            colors: looksEnabled ? enabledColors : disabledColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Content scrolling under the buttons fades out instead of being cut off.
    private var barBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Color.paeoniaBackgroundPrimary.opacity(0), location: 0),
                .init(color: Color.paeoniaBackgroundPrimary.opacity(0.96), location: 0.16),
                .init(color: Color.paeoniaBackgroundPrimary, location: 0.3),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
