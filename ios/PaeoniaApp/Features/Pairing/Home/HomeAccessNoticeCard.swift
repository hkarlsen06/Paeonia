import StoreKit
import SwiftUI

/// The Home notice about the subscription (`AccessNotice`). It stays until the payment goes through,
/// renewal is back on, the reminder's days are over, or this person closes it. The person who pays
/// gets a button to Apple's subscription page, the same sheet Settings opens.
struct HomeAccessNoticeCard: View {
    let notice: AccessNotice
    let onDismiss: () -> Void

    @State private var isManagingSubscription = false

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                HStack(alignment: .top, spacing: PaeoniaSpacing.space12) {
                    text
                    closeButton
                }
                if let buttonTitle {
                    Button {
                        isManagingSubscription = true
                    } label: {
                        Text(buttonTitle)
                    }
                    .buttonStyle(PaeoniaSecondaryButtonStyle())
                }
            }
        }
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
    }

    private var text: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space12) {
            Image(systemName: systemImage)
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(title)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                if let message {
                    Text(message)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Outside the combined text element, so VoiceOver reaches it as its own button.
    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .background(.paeoniaSurfaceSecondary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.paeoniaPressableCard)
        .accessibilityLabel(Text(.commonClose))
        .accessibilityIdentifier("home.accessNotice.close")
    }

    private var systemImage: String {
        switch notice {
        case .paymentProblem: "creditcard"
        case .ending: "calendar"
        case .running: "arrow.triangle.2.circlepath"
        }
    }

    private var title: LocalizedStringResource {
        switch notice {
        case .paymentProblem:
            .homeAccessNoticePaymentTitle
        case let .ending(endsAt, _):
            .homeAccessNoticeEndingTitle(endsAt.formatted(.dateTime.day().month(.abbreviated)))
        case .running:
            .homeAccessNoticeRunningTitle
        }
    }

    private var message: LocalizedStringResource? {
        switch notice {
        case .paymentProblem: .homeAccessNoticePaymentMessage
        case .ending(_, canRenew: true): .homeAccessNoticeEndingPayerMessage
        case .ending(_, canRenew: false): nil
        case let .running(renewsAt, _):
            .homeAccessNoticeRunningMessage(renewsAt.formatted(.dateTime.day().month(.wide).year()))
        }
    }

    private var buttonTitle: LocalizedStringResource? {
        switch notice {
        case .paymentProblem: .homeAccessNoticePaymentButton
        case .ending(_, canRenew: true): .homeAccessNoticeEndingButton
        case .ending(_, canRenew: false): nil
        case .running: .homeAccessNoticeRunningButton
        }
    }
}
