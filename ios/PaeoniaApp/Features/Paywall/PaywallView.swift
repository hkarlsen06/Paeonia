import Foundation
import StoreKit
import SwiftUI

struct PaywallView: View {
    @State private var viewModel: PaywallViewModel

    let onPurchaseConfirmed: () -> Void
    let onAcceptInvite: () -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    @State private var isConfirmingDelete = false
    @State private var inviteCode = ""
    @State private var showInviteOverlay = false
    @FocusState private var inviteFieldFocused: Bool

    init(
        session: AuthSession?,
        onPurchaseConfirmed: @escaping () -> Void,
        onAcceptInvite: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
        onDeleteAccount: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: PaywallViewModel(userID: session?.id))
        self.onPurchaseConfirmed = onPurchaseConfirmed
        self.onAcceptInvite = onAcceptInvite
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.paeoniaSurfacePrimary
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        paywallContent(geometry: geometry)
                        paywallErrorMessage
                            .padding(.top, PaeoniaSpacing.space16)
                        footerActions
                            .padding(.horizontal, PaeoniaSpacing.space20)
                            .padding(.top, PaeoniaSpacing.space32)
                    }
                    .padding(.bottom, PaeoniaSpacing.space16)
                    .frame(maxWidth: .infinity)
                    .background(.paeoniaSurfacePrimary)
                }
                .scrollDismissesKeyboard(.immediately)
                .ignoresSafeArea(edges: .top)

                if showInviteOverlay {
                    inviteOverlay
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                }
            }
            .safeAreaInset(edge: .bottom) {
                PaywallBottomCTAView(
                    title: ctaTitle,
                    caption: ctaCaption,
                    isEnabled: ctaIsEnabled,
                    isBusy: isInviteMode ? false : viewModel.isPurchasing,
                    usesSolidBackground: isInviteMode,
                    action: ctaAction
                )
            }
        }
        .task {
            await viewModel.loadProducts()
        }
        .confirmationDialog(
            Text(.authDeleteAccountConfirmTitle),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: onDeleteAccount) {
                Text(.authDeleteAccountConfirmAction)
            }

            Button(role: .cancel, action: {}) {
                Text(.authDeleteAccountConfirmCancel)
            }
        } message: {
            Text(.authDeleteAccountConfirmMessage)
        }
    }

    // MARK: - Invite Overlay

    private var inviteOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.3))
                .ignoresSafeArea()
                .onTapGesture { dismissInviteOverlay() }
                .accessibilityLabel(Text(.paywallInviteDismiss))
                .accessibilityAddTraits(.isButton)

            PaywallInviteCodeView(
                code: $inviteCode,
                focus: $inviteFieldFocused,
                onSubmit: submitInvite
            )
            .padding(.horizontal, PaeoniaSpacing.space20)
        }
        .task { await focusInviteFieldAfterPresentation() }
    }

    // MARK: - Content

    private func paywallContent(geometry: GeometryProxy) -> some View {
        PaywallContentView(
            topSafeAreaInset: geometry.safeAreaInsets.top,
            heroHeight: heroHeight(for: geometry),
            aboveFoldMinHeight: aboveFoldMinHeight(for: geometry),
            billingPeriod: $viewModel.billingPeriod,
            headlineTitle: headlineTitle,
            priceLine: priceLine,
            timelineItems: timelineItems,
            onRevealInvite: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showInviteOverlay = true
                }
            }
        )
    }

    private func submitInvite() {
        if inviteCode.count == PaywallInviteCodeView.codeLength {
            redeemInvite()
        } else if !inviteCode.isEmpty {
            inviteFieldFocused = true
        }
    }

    private func heroHeight(for geometry: GeometryProxy) -> CGFloat {
        let band = min(max(geometry.size.height * 0.15, 128), 156)
        return geometry.safeAreaInsets.top + band
    }

    private func aboveFoldMinHeight(for geometry: GeometryProxy) -> CGFloat {
        geometry.size.height + geometry.safeAreaInsets.top - 120
    }

    // MARK: - Bottom CTA

    private var isInviteMode: Bool {
        showInviteOverlay
    }

    private var ctaTitle: LocalizedStringResource {
        isInviteMode ? .paywallInviteAction : primaryButtonTitle
    }

    private var ctaCaption: LocalizedStringResource {
        isInviteMode ? .paywallInviteCtaCaption : .paywallCancelAnytime
    }

    private var ctaIsEnabled: Bool {
        if isInviteMode {
            return inviteCode.count == PaywallInviteCodeView.codeLength
        }
        return primaryButtonIsEnabled
    }

    private func ctaAction() {
        if isInviteMode {
            redeemInvite()
        } else {
            purchase()
        }
    }

    private func redeemInvite() {
        dismissInviteOverlay()
        onAcceptInvite()
    }

    private func focusInviteFieldAfterPresentation() async {
        await Task.yield()

        await MainActor.run {
            guard showInviteOverlay else {
                return
            }

            inviteFieldFocused = true
        }
    }

    private func dismissInviteOverlay() {
        inviteFieldFocused = false

        Task { @MainActor in
            await Task.yield()

            inviteFieldFocused = false
            showInviteOverlay = false
        }
    }

    @ViewBuilder
    private var paywallErrorMessage: some View {
        if let error = viewModel.error {
            HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.paeoniaError)
                    .accessibilityHidden(true)

                Text(error.message)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaError)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(PaeoniaSpacing.space12)
            .background(Color.paeoniaError.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: 430)
        }
    }

    private var footerActions: some View {
        PaywallFooterActionsView(
            isPurchasing: viewModel.isPurchasing,
            isLoading: viewModel.isLoading,
            onRestorePurchases: restorePurchases,
            onSignOut: onSignOut,
            onRequestDeleteAccount: {
                isConfirmingDelete = true
            }
        )
    }

    private var primaryButtonIsEnabled: Bool {
        viewModel.currentProduct != nil && !viewModel.isPurchasing && !viewModel.isLoading
    }

    private var primaryButtonTitle: LocalizedStringResource {
        if viewModel.isPurchasing {
            return .paywallCtaPurchasing
        }

        if viewModel.currentFreeTrial != nil {
            return .paywallCtaFreeTrial
        }

        return .paywallCtaSubscribe
    }

    private var headlineTitle: LocalizedStringResource {
        if viewModel.currentFreeTrial != nil {
            return .paywallTrialTitle
        }

        return .paywallTitle
    }

    private var priceLine: String {
        guard let product = viewModel.currentProduct else {
            return String(localized: .paywallPriceLoading)
        }

        let renewal = "\(compactDisplayPrice(for: product))\(String(localized: compactPeriodLabel))"
        guard let freeTrial = viewModel.currentFreeTrial else {
            return renewal
        }

        let freeWord = String(localized: .paywallTrialFreeWord)
        let then = String(localized: .paywallTrialThen)
            .lowercased(with: Locale.current)

        return "\(freeTrial.localizedDurationText) \(freeWord), \(then) \(renewal)"
    }

    private var timelineItems: [PaywallTimelineItem] {
        if viewModel.currentFreeTrial != nil {
            return [
                PaywallTimelineItem(
                    id: "today",
                    title: String(localized: .paywallTimelineToday),
                    message: String(localized: .paywallTimelineTodayBody),
                    systemImage: "lock.open.fill",
                    isActive: true
                ),
                PaywallTimelineItem(
                    id: "reminder",
                    title: trialTimelineDayTitle(day: trialReminderDay),
                    message: String(localized: .paywallTimelineReminderBody),
                    systemImage: "bell.fill",
                    isActive: false
                ),
                PaywallTimelineItem(
                    id: "charge",
                    title: trialTimelineDayTitle(day: trialDurationDay),
                    message: String(localized: .paywallTimelineChargeBody),
                    systemImage: "calendar.badge.clock",
                    isActive: false
                ),
            ]
        }

        return [
            PaywallTimelineItem(
                id: "today",
                title: String(localized: .paywallTimelineToday),
                message: String(localized: .paywallTimelineTodayBody),
                systemImage: "lock.open.fill",
                isActive: true
            ),
            PaywallTimelineItem(
                id: "manage",
                title: String(localized: .paywallTimelineManage),
                message: String(localized: .paywallTimelineManageBody),
                systemImage: "gearshape.fill",
                isActive: false
            ),
            PaywallTimelineItem(
                id: "renewal",
                title: String(localized: .paywallTimelineRenewal),
                message: String(localized: renewalTimelineBody),
                systemImage: "calendar",
                isActive: false
            ),
        ]
    }

    private var trialDurationDay: Int {
        viewModel.currentFreeTrial?.approximateDayCount ?? 14
    }

    private var trialReminderDay: Int {
        max(trialDurationDay - 2, 1)
    }

    private func trialTimelineDayTitle(day: Int) -> String {
        "\(String(localized: .paywallTimelineDayPrefix)) \(day)"
    }

    private var renewalTimelineBody: LocalizedStringResource {
        switch viewModel.billingPeriod {
        case .monthly:
            .paywallTimelineRenewalMonthlyBody
        case .yearly:
            .paywallTimelineRenewalYearlyBody
        }
    }

    private var compactPeriodLabel: LocalizedStringResource {
        switch viewModel.billingPeriod {
        case .monthly:
            .paywallPeriodMonthlyCompact
        case .yearly:
            .paywallPeriodYearlyCompact
        }
    }

    private func compactDisplayPrice(for product: Product) -> String {
        var price = product.price
        var rounded = Decimal()
        NSDecimalRound(&rounded, &price, 0, .plain)

        if rounded == product.price {
            return product.price.formatted(product.priceFormatStyle.precision(.fractionLength(0)))
        }

        return product.displayPrice
    }

    private func purchase() {
        Task {
            let didPurchase = await viewModel.purchaseSelectedProduct()
            if didPurchase {
                onPurchaseConfirmed()
            }
        }
    }

    private func restorePurchases() {
        Task {
            let didRestore = await viewModel.restorePurchases()
            if didRestore {
                onPurchaseConfirmed()
            }
        }
    }
}

#Preview {
    PaywallView(
        session: AuthSession(
            id: UUID().uuidString,
            provider: .apple,
            displayName: "Alvilde",
            timeZoneID: "Europe/Oslo",
            profileStatus: .complete
        ),
        onPurchaseConfirmed: {},
        onAcceptInvite: {},
        onSignOut: {},
        onDeleteAccount: {}
    )
    .preferredColorScheme(.dark)
}
