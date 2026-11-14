import SwiftUI

/// The More tab's last section: the subscription, privacy and safety, and support,
/// with the legal links and the app version in its footer.
struct SettingsSubscriptionHelpSection: View {
    let viewModel: SettingsViewModel
    let onPurchasesRestored: @MainActor @Sendable () async -> Void
    let partnerUserID: UUID?
    let partnerName: String
    let privacySafetyService: (any PrivacySafetyServicing)?
    let privacyOperationProvider: (any SyncClientOperationProviding)?
    let onLeftRelationship: () -> Void

    var body: some View {
        Section {
            NavigationLink {
                PurchaseSettingsView(viewModel: viewModel, onPurchasesRestored: onPurchasesRestored)
                    .analyticsScreen("settings_purchases")
            } label: {
                SettingsMenuLabel(
                    .settingsPurchasesSectionTitle,
                    systemImage: "creditcard.fill",
                    value: subscriptionValue
                )
            }

            // Privacy requests and reporting share one screen. Reporting ends the
            // relationship, so it waits there behind a deliberate tap instead of
            // sitting on the menu.
            NavigationLink {
                PrivacySafetyView(
                    partnerUserID: partnerUserID,
                    partnerName: partnerName,
                    service: privacySafetyService,
                    operationProvider: privacyOperationProvider,
                    onReportedAndLeft: onLeftRelationship
                )
                .analyticsScreen("privacy_safety")
            } label: {
                SettingsMenuLabel(.privacySafetyTitle, systemImage: "checkmark.shield.fill")
            }
            .accessibilityIdentifier("settings.privacy")

            supportRow
        } header: {
            Text(.settingsSectionSubscriptionHelp)
        } footer: {
            VStack(spacing: 0) {
                PaeoniaLegalLinksView()
                if let versionLine {
                    versionLine
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, PaeoniaSpacing.space16)
        }
    }

    private var subscriptionValue: Text? {
        guard case let .loaded(details) = viewModel.subscriptionDetailsState else {
            return nil
        }
        return Text(details.status.title)
    }

    private var versionLine: Text? {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String,
              let build = info?["CFBundleVersion"] as? String
        else {
            return nil
        }
        return Text(.settingsVersion(version, build))
    }

    @ViewBuilder
    private var supportRow: some View {
        if let supportURL = URL(string: "https://paeonia.no/support") {
            Link(destination: supportURL) {
                LabeledContent {
                    Image(systemName: "arrow.up.right")
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .accessibilityHidden(true)
                } label: {
                    SettingsMenuLabel(.authSignInSupport, systemImage: "questionmark.circle.fill")
                }
            }
        }
    }
}
