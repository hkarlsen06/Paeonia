import Foundation
import SwiftUI

/// The subscription offer, shown in the root's branded frame between profile setup
/// and pairing. It shows right away; only the prices wait for the App Store, as
/// placeholders, so nothing jumps when they arrive.
struct PaywallView: View {
    @State private var viewModel: PaywallViewModel
    @Binding private var pendingInviteCode: String?
    private let presentationOverride: PaywallPresentationOverride?
    /// The root is checking access after a purchase or a join.
    private let isCheckingAccess: Bool
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    let onPurchaseConfirmed: () -> Void
    let onInviteAccepted: () -> Void
    let audience: PaywallAudience
    let onSignOut: () -> Void
    let onUnpaired: () -> Void
    let onDeleteAccount: () -> Void

    @State private var isConfirmingDelete = false
    @State private var isConfirmingUnpair = false
    @State private var isConfirmingInvite = false
    @State private var isEnteringInviteCode = false
    /// A purchase, restore, or join went through and the next screen is on its
    /// way. The buttons wait instead of offering to buy again. If the access check
    /// ends with the paywall still up, they come back.
    @State private var isOpening = false
    /// The scroll view's height between the logo and the buy button.
    @State private var visibleHeight: CGFloat = 0
    /// The offer drops in once the prices are in, so they don't swap in halfway
    /// through the drop. A slow App Store only holds it for a moment.
    @State private var isEntranceReady = false

    init(
        session: AuthSession?,
        pendingInviteCode: Binding<String?> = .constant(nil),
        audience: PaywallAudience,
        isCheckingAccess: Bool = false,
        onPurchaseConfirmed: @escaping () -> Void,
        onInviteAccepted: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
        onUnpaired: @escaping () -> Void,
        onDeleteAccount: @escaping () -> Void,
        viewModel: PaywallViewModel? = nil,
        presentationOverride: PaywallPresentationOverride? = nil
    ) {
        _viewModel = State(
            initialValue: viewModel ?? PaywallViewModel(userID: session?.id)
        )
        _pendingInviteCode = pendingInviteCode
        self.presentationOverride = presentationOverride
        self.isCheckingAccess = isCheckingAccess
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
        ScrollView {
            VStack(spacing: 0) {
                PaywallContentView(
                    audience: audience,
                    plans: plans,
                    isLoadingPlans: selectedPresentation.isLoading,
                    showsTrialReminder: selectedPresentation.hasFreeTrial,
                    isEntranceReady: isEntranceReady,
                    billingPeriod: $viewModel.billingPeriod
                )
                // The offer fills the first screen, so restore, legal links and
                // account actions only show once someone scrolls to them.
                .frame(minHeight: visibleHeight, alignment: .top)

                footerActions
                    .padding(.top, PaeoniaSpacing.space40)
            }
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space16)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // The container already stops at the top of the bottom bar, even though
        // the content insets also count the bar.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height
        } action: { _, height in
            visibleHeight = height
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .task {
            guard presentationOverride == nil else {
                return
            }
            await viewModel.loadProducts()
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            isEntranceReady = true
        }
        .onChange(of: selectedPresentation.isLoading, initial: true) { _, isLoading in
            if !isLoading {
                isEntranceReady = true
            }
        }
        .task(id: allowsInviteEntry ? pendingInviteCode : nil) {
            await previewPendingInvite()
        }
        .onChange(of: viewModel.error) { _, error in
            showBanner(for: error)
        }
        .onChange(of: isCheckingAccess) { wasChecking, isChecking in
            if wasChecking, !isChecking {
                isOpening = false
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.purchaseSucceeded) { _, succeeded in
            succeeded
        }
        .sheet(isPresented: $isEnteringInviteCode, onDismiss: confirmInviteIfPreviewed) {
            PairingCodeEntrySheet(
                title: .pairingCodeEntryTitle,
                message: .paywallInviteSheetMessage,
                submitTitle: .pairingCodeEntrySubmit,
                onSubmit: previewEnteredInvite
            )
        }
        .modifier(
            PaywallConfirmationAlerts(
                isConfirmingDelete: $isConfirmingDelete,
                isConfirmingUnpair: $isConfirmingUnpair,
                isConfirmingInvite: $isConfirmingInvite,
                partnerName: audience.partnerNameForCopy,
                invitePreview: viewModel.invitePreview,
                onDeleteAccount: onDeleteAccount,
                onUnpair: unpair,
                onAcceptInvite: redeemPreviewedInvite,
                onCancelInvite: cancelInviteConfirmation
            )
        )
    }
}

private extension PaywallView {
    // MARK: - Offer

    /// Trial copy waits until the App Store has said whether this account can
    /// still get the trial, so nobody sees a trial that then disappears.
    func presentation(for period: PaeoniaBillingPeriod) -> PaywallPresentation {
        if let presentationOverride {
            return presentationOverride.presentation(period)
        }

        let isReady = viewModel.isPresentationReady
        return PaywallPresentation(
            billingPeriod: period,
            product: isReady ? viewModel.product(for: period) : nil,
            freeTrial: isReady ? viewModel.freeTrial(for: period) : nil,
            isPurchasing: viewModel.isPurchasing,
            isLoading: viewModel.isLoading || !isReady
        )
    }

    var selectedPresentation: PaywallPresentation {
        presentation(for: viewModel.billingPeriod)
    }

    var plans: [PaywallPlanOption] {
        PaywallPlanOption.options(
            monthly: presentation(for: .monthly),
            yearly: presentation(for: .yearly)
        )
    }

    // MARK: - Bottom bar

    var bottomBar: some View {
        let selected = selectedPresentation
        let hasOffer = presentationOverride != nil || selected.product != nil
        let canRetry = !hasOffer && !selected.isLoading
        let title: LocalizedStringResource = canRetry ? .paywallProductsRetry : selected.primaryButtonTitle
        let isEnabled: Bool = presentationOverride?.purchaseIsEnabled
            ?? (hasOffer ? selected.primaryButtonIsEnabled : canRetry)
        var inviteAction: (() -> Void)?
        if allowsInviteEntry {
            inviteAction = { showInviteCodeEntry() }
        }

        return PaywallBottomCTAView(
            title: title,
            caption: selected.billingDisclosure,
            isEnabled: isEnabled,
            isBusy: hasOffer ? selected.isPurchasing : selected.isLoading,
            isDone: isOpening,
            isJoiningPartner: viewModel.isPreviewingInvite || viewModel.isAcceptingInvite,
            onPrimaryAction: {
                if hasOffer {
                    purchase()
                } else {
                    retryProducts()
                }
            },
            onHaveInviteCode: inviteAction
        )
    }

    var footerActions: some View {
        PaywallFooterActionsView(
            isBusyWithStore: viewModel.isBusyWithStore || isOpening,
            isRestoring: viewModel.isRestoring,
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

    // MARK: - Store actions

    func purchase() {
        Task {
            let didPurchase: Bool
            if let presentationOverride {
                didPurchase = await presentationOverride.onPurchase()
            } else {
                didPurchase = await viewModel.purchaseSelectedProduct()
            }
            if didPurchase {
                startOpening(then: onPurchaseConfirmed)
            }
        }
    }

    func retryProducts() {
        Task {
            await viewModel.loadProducts()
            if viewModel.currentProduct != nil {
                bannerCenter.dismiss()
            }
        }
    }

    func restorePurchases() {
        Task {
            if await viewModel.restorePurchases() {
                startOpening(then: onPurchaseConfirmed)
            }
        }
    }

    func startOpening(then next: () -> Void) {
        isOpening = true
        next()
    }

    func unpair() {
        Task {
            let didLeave = await viewModel.leaveRelationship()
            if didLeave {
                bannerCenter.dismiss()
                onUnpaired()
            }
        }
    }

    func showBanner(for error: PaywallError?) {
        guard let error else {
            return
        }

        bannerCenter.show(error.bannerContent)
        viewModel.clearError()
    }

    // MARK: - Joining a partner

    /// An earlier preview that was never accepted would otherwise come back as
    /// the confirmation when the sheet closes.
    func showInviteCodeEntry() {
        viewModel.clearInvitePreview()
        isEnteringInviteCode = true
    }

    /// A code saved from a link or the welcome screen goes straight to the
    /// confirmation, without the code sheet.
    func previewPendingInvite() async {
        // A code typed in the sheet is saved as the pending code once it previews.
        // That save is not a second request to preview it, so a code with a
        // preview already in hand is left alone.
        guard allowsInviteEntry,
              let pendingInviteCode,
              viewModel.invitePreview == nil,
              !isEnteringInviteCode,
              !isConfirmingInvite
        else {
            return
        }

        if await viewModel.previewInvite(codeInput: pendingInviteCode) != nil {
            isConfirmingInvite = true
        } else if viewModel.lastInviteCodeWasUnusable {
            // A wrong or expired code would otherwise come back on every launch.
            self.pendingInviteCode = nil
        }
    }

    /// Keeps the sheet open with the keyboard up when the code doesn't work. The
    /// banner says why.
    func previewEnteredInvite(_ code: String) async -> Bool {
        guard await viewModel.previewInvite(codeInput: code) != nil else {
            return false
        }

        // Remember only a code that works, so a typo is not reopened on the next
        // launch.
        pendingInviteCode = code
        return true
    }

    /// Runs after the code sheet has closed. Showing the alert any earlier can lose
    /// it to the sheet's closing animation.
    func confirmInviteIfPreviewed() {
        if viewModel.invitePreview != nil {
            isConfirmingInvite = true
        }
    }

    func redeemPreviewedInvite() {
        guard !viewModel.isAcceptingInvite else {
            return
        }

        Task {
            if await viewModel.acceptPreviewedInvite() {
                bannerCenter.dismiss()
                // Root clears the pending code once the paired route is in place.
                // Clearing it here would route back to pairing for a frame first.
                startOpening(then: onInviteAccepted)
            }
        }
    }

    /// "Not now" also forgets a code that came from a link, so it doesn't ask again
    /// on the next launch.
    func cancelInviteConfirmation() {
        viewModel.clearInvitePreview()
        pendingInviteCode = nil
    }
}
