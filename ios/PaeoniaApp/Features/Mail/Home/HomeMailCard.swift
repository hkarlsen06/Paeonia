import SwiftUI

/// The Mail card on the Us tab. A letter that waits for this person shows as a sealed
/// envelope that opens it. Otherwise the card offers to write one. The mailbox is a tap away
/// in both cases.
struct HomeMailCard: View {
    let mail: MailViewModel
    let partnerName: String

    @ScaledMetric(relativeTo: .body) private var artWidth: CGFloat = 76
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let waiting = mail.waiting
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                header
                Button {
                    if let letter = waiting.first {
                        mail.present(MailPresentation(path: [.reader(letter.id)]))
                    } else {
                        mail.present(MailPresentation(path: [.composer], tab: .sent))
                    }
                } label: {
                    row(waiting: waiting)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(waiting.isEmpty ? "home.mail.write" : "home.mail.open")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space12) {
            Label {
                Text(.mailCardTitle)
            } icon: {
                Image(systemName: "envelope.fill")
            }
            .labelStyle(.titleAndIcon)
            .paeoniaEyebrowStyle(foreground: .paeoniaAccentPrimary)
            Spacer(minLength: PaeoniaSpacing.space8)
            Button {
                mail.present()
            } label: {
                Text(.mailMailboxTitle)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.mail.mailbox")
        }
    }

    private func row(waiting: [Letter]) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: PaeoniaSpacing.space16))
        let width = min(artWidth, 120)
        return layout {
            if waiting.isEmpty {
                Image(.mailTemplateBlank)
                    .resizable()
                    .accessibilityHidden(true)
                    .scaledToFit()
                    .frame(width: width, height: width)
            } else {
                MailSealedEnvelope(width: width)
            }
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(title(waiting: waiting.count))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(waiting.isEmpty ? .mailCardEmptyMessage(partnerName) : .mailCardWaitingMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func title(waiting count: Int) -> LocalizedStringResource {
        switch count {
        case 0: .mailCardWrite
        case 1: .mailCardWaitingOne(partnerName)
        default: .mailCardWaitingMany(count, partnerName)
        }
    }
}
