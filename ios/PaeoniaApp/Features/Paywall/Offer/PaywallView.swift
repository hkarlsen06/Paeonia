import Foundation
import SwiftUI

// swiftlint:disable:next type_body_length
struct PaywallView: View {
    @State private var viewModel: PaywallViewModel
    @Binding private var pendingInviteCode: String?
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onPurchaseConfirmed: () -> Void
    let onInviteAccepted: () -> Void
    let audience: PaywallAudience
    let onSignOut: () -> Void
    let onUnpaired: () -> Void
    let onDeleteAccount: () -> Void

    @State private var isConfirmingDelete = false
    @State private var isConfirmingUnpair = false
    @State private var inviteCode = ""
    @State private var showInviteOverlay = false
    @State private var hasPresentedPaywallContent = false
    @FocusState private var inviteFieldFocused: Bool

    init(
        session: AuthSession?,
        pendingInviteCode: Binding<String?> = .constant(nil),
        audience: PaywallAudience,
        onPurchaseConfirmed: @escaping () -> Void,
        onInviteAccepted: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
        onUnpaired: @escaping () -> Void,
        onDeleteAccount: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: PaywallViewModel(userID: session?.id))
        _pendingInviteCode = pendingInviteCode
        self.audience = audience
        self.onPurchaseConfirmed = onPurchaseConfirmed
        self.onInviteAccepted = onInviteAccepted
        self.onSignOut = onSignOut
        self.onUnpaired = onUnpaired
        self.onDeleteAccount = onDeleteAccount
    }

    private var allowsInviteEntry: Bool {
        audience.allowsInviteEntry
    }

    var body: some View {
        Group {
            if viewModel.isPresentationReady {
                GeometryReader { geometry in
                    paywallScene(geometry: geometry)
                }
            } else {
                AuthLaunchingView()
            }
        }
        .task {
            await viewModel.loadProducts()
        }
        .task(id: viewModel.isPresentationReady) {
            await presentPaywallContentIfReady()
        }
        .task(id: pendingInviteCode) {
            await presentPendingInviteIfAvailable()
        }
        .task(id: allowsInviteEntry) {
            await presentPendingInviteIfAvailable()
        }
        .onChange(of: viewModel.error) { _, error in
            showBanner(for: error)
        }
        .alert(
            Text(.authDeleteAccountConfirmTitle),
            isPresented: $isConfirmingDelete
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
        .alert(
            Text(.paywallUnpairConfirmTitle(audience.partnerNameForCopy)),
            isPresented: $isConfirmingUnpair
        ) {
            Button(role: .destructive, action: unpair) {
                Text(.paywallUnpairConfirmAction)
            }

            Button(role: .cancel, action: {}) {
                Text(.paywallUnpairConfirmCancel)
            }
        } message: {
            Text(.paywallUnpairConfirmMessage(audience.partnerNameForCopy))
        }
    }

    private func paywallScene(geometry: GeometryProxy) -> some View {
        ZStack {
            Color.paeoniaSurfacePrimary
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    paywallContent(geometry: geometry)
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
            .opacity(paywallEntranceOpacity)
            .offset(y: paywallEntranceOffset)

            if showInviteOverlay {
                inviteOverlay
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomCTA
                .opacity(paywallEntranceOpacity)
                .offset(y: paywallEntranceOffset)
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
            subtitle: subtitle,
            priceLine: presentation.priceLine,
            timelineItems: presentation.timelineItems,
            allowsInviteEntry: allowsInviteEntry,
            showsArtworkHeader: !audience.isPaired,
            onRevealInvite: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showInviteOverlay = true
                }
                inviteFieldFocused = true
            }
        )
    }

    /// Paired couples without an active subscription get copy that makes it clear
    /// they are still linked; everyone else gets the standard acquisition headline.
    private var headlineTitle: LocalizedStringResource {
        if audience.isPaired {
            return .paywallPairedTitle(audience.partnerNameForCopy)
        }

        return presentation.headlineTitle
    }

    private var subtitle: LocalizedStringResource {
        audience.isPaired ? .paywallPairedSubtitle : .paywallSubtitle
    }

    private func submitInvite() {
        let sanitizedCode = PaywallInviteCodeView.sanitize(inviteCode)
        if sanitizedCode != inviteCode {
            inviteCode = sanitizedCode
        }

        if sanitizedCode.count == PaywallInviteCodeView.codeLength {
            redeemInvite(codeInput: sanitizedCode)
        } else if !sanitizedCode.isEmpty {
            inviteFieldFocused = true
        }
    }

    @MainActor
    private func presentPendingInviteIfAvailable() async {
        guard allowsInviteEntry,
              let pendingCode = pendingInviteCode,
              let normalizedCode = try? PairingInviteCode.normalized(pendingCode)
        else {
            return
        }

        inviteCode = normalizedCode
        self.pendingInviteCode = nil

        withAnimation(.easeInOut(duration: 0.25)) {
            showInviteOverlay = true
        }

        await focusInviteFieldAfterPresentation()
    }

    private func heroHeight(for geometry: GeometryProxy) -> CGFloat {
        let band = min(max(geometry.size.height * 0.15, 128), 156)
        return geometry.safeAreaInsets.top + band
    }

    private func aboveFoldMinHeight(for geometry: GeometryProxy) -> CGFloat {
        geometry.size.height + geometry.safeAreaInsets.top - 120
    }

    // MARK: - Bottom CTA

    private var bottomCTA: some View {
        PaywallBottomCTAView(
            title: ctaTitle,
            caption: ctaCaption,
            isEnabled: ctaIsEnabled,
            isBusy: isInviteMode ? viewModel.isAcceptingInvite : viewModel.isPurchasing,
            usesSolidBackground: isInviteMode,
            action: ctaAction
        )
    }

    private var isInviteMode: Bool {
        showInviteOverlay
    }

    private var paywallEntranceOpacity: Double {
        hasPresentedPaywallContent ? 1 : 0
    }

    private var paywallEntranceOffset: CGFloat {
        hasPresentedPaywallContent || reduceMotion ? 0 : -10
    }

    private var ctaTitle: LocalizedStringResource {
        isInviteMode ? .paywallInviteAction : presentation.primaryButtonTitle
    }

    private var ctaCaption: LocalizedStringResource {
        isInviteMode ? .paywallInviteCtaCaption : .paywallCancelAnytime
    }

    private var ctaIsEnabled: Bool {
        if isInviteMode {
            return PaywallInviteCodeView.sanitize(inviteCode).count == PaywallInviteCodeView.codeLength
                && !viewModel.isAcceptingInvite
        }
        return presentation.primaryButtonIsEnabled
    }

    private func ctaAction() {
        if isInviteMode {
            submitInvite()
        } else {
            purchase()
        }
    }

    private func redeemInvite(codeInput: String) {
        guard !viewModel.isAcceptingInvite else {
            return
        }

        Task {
            let didAccept = await viewModel.acceptInvite(codeInput: codeInput)
            if didAccept {
                viewModel.clearError()
                bannerCenter.dismiss()
                onInviteAccepted()
            } else {
                inviteFieldFocused = true
            }
        }
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

    private var footerActions: some View {
        PaywallFooterActionsView(
            isPurchasing: viewModel.isPurchasing,
            isLoading: viewModel.isLoading,
            showsUnpair: audience.isPaired,
            isLeavingRelationship: viewModel.isLeavingRelationship,
            onRestorePurchases: restorePurchases,
            onSignOut: onSignOut,
            onRequestUnpair: {
                isConfirmingUnpair = true
            },
            onRequestDeleteAccount: {
                isConfirmingDelete = true
            }
        )
    }

    private var presentation: PaywallPresentation {
        PaywallPresentation(
            billingPeriod: viewModel.billingPeriod,
            product: viewModel.currentProduct,
            freeTrial: viewModel.currentFreeTrial,
            isPurchasing: viewModel.isPurchasing,
            isLoading: viewModel.isLoading
        )
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

    private func unpair() {
        Task {
            let didLeave = await viewModel.leaveRelationship()
            if didLeave {
                bannerCenter.dismiss()
                onUnpaired()
            }
        }
    }

    private func showBanner(for error: PaywallError?) {
        guard let error else {
            return
        }

        bannerCenter.show(.error(message: error.message))
        viewModel.clearError()
    }

    private func presentPaywallContentIfReady() async {
        guard viewModel.isPresentationReady else {
            hasPresentedPaywallContent = false
            return
        }

        await Task.yield()

        if reduceMotion {
            hasPresentedPaywallContent = true
        } else {
            withAnimation(.easeOut(duration: PaeoniaMotion.motionSlow)) {
                hasPresentedPaywallContent = true
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
            profilePhotoAssetID: nil,
            profileStatus: .complete
        ),
        audience: .unpaired,
        onPurchaseConfirmed: {},
        onInviteAccepted: {},
        onSignOut: {},
        onUnpaired: {},
        onDeleteAccount: {}
    )
    .preferredColorScheme(.dark)
    .environment(PaeoniaBannerCenter())
}
