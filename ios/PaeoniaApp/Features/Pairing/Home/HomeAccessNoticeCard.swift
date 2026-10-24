import StoreKit
import SwiftUI

/// The Home notice before access ends (`AccessNotice`). It stays until the payment goes through or
/// renewal is back on. The person who pays gets a button to Apple's subscription page, the same
/// sheet Settings opens.
struct HomeAccessNoticeCard: View {
    let notice: AccessNotice

    @State private var isManagingSubscription = false

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
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
                .accessibilityElement(children: .combine)
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

    private var systemImage: String {
        switch notice {
        case .paymentProblem: "creditcard"
        case .ending: "calendar"
        }
    }

    private var title: LocalizedStringResource {
        switch notice {
        case .paymentProblem:
            .homeAccessNoticePaymentTitle
        case let .ending(endsAt, _):
            .homeAccessNoticeEndingTitle(endsAt.formatted(.dateTime.day().month(.abbreviated)))
        }
    }

    private var message: LocalizedStringResource? {
        switch notice {
        case .paymentProblem: .homeAccessNoticePaymentMessage
        case .ending(_, canRenew: true): .homeAccessNoticeEndingPayerMessage
        case .ending(_, canRenew: false): nil
        }
    }

    private var buttonTitle: LocalizedStringResource? {
        switch notice {
        case .paymentProblem: .homeAccessNoticePaymentButton
        case .ending(_, canRenew: true): .homeAccessNoticeEndingButton
        case .ending(_, canRenew: false): nil
        }
    }
}
