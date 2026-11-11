import SwiftUI

/// The Mail card on the Us tab. A letter that waits for this person shows as a sealed
/// envelope that opens it. Otherwise one short row offers to write a letter, or to finish the
/// one being written where the person left it, so the cards under it stay on the first screen.
/// The mailbox is a tap away in every case. A problem that came up after the Mail sheet closed
/// shows here.
struct HomeMailCard: View {
    let mail: MailViewModel
    let partnerName: String

    private static let iconSize: CGFloat = 32

    @ScaledMetric(relativeTo: .body) private var artWidth: CGFloat = 76
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        let waiting = mail.waiting
        Group {
            if waiting.isEmpty {
                writeRow(isDraft: mail.composer.draft != nil)
            } else {
                waitingCard(waiting)
            }
        }
        .mailNotices(mail, bannerCenter: bannerCenter, when: mail.presentation == nil)
    }

    /// As tall as the locked answer row, like the visit question.
    private func writeRow(isDraft: Bool) -> some View {
        PaeoniaCard(padding: PaeoniaSpacing.space12) {
            HStack(spacing: PaeoniaSpacing.space8) {
                Button {
                    mail.present(MailPresentation(path: [.composer], tab: .sent))
                } label: {
                    HStack(spacing: PaeoniaSpacing.space12) {
                        Image(systemName: isDraft ? "pencil.line" : "envelope.fill")
                            .font(PaeoniaTypography.caption.weight(.semibold))
                            .foregroundStyle(.paeoniaAccentPrimary)
                            .frame(width: Self.iconSize, height: Self.iconSize)
                            .background(.paeoniaSurfaceSecondary, in: Circle())
                            .accessibilityHidden(true)
                        Text(isDraft ? .mailCardDraft(partnerName) : .mailCardWriteTo(partnerName))
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(isDraft ? "home.mail.draft" : "home.mail.write")
                mailboxButton
            }
        }
    }

    private func waitingCard(_ waiting: [Letter]) -> some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                header
                Button {
                    if let letter = waiting.first {
                        mail.present(MailPresentation(path: [.reader(letter.id)]))
                    }
                } label: {
                    row(waiting: waiting)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.mail.open")
            }
        }
    }

    private var mailboxButton: some View {
        Button {
            mail.present()
        } label: {
            Text(.mailMailboxTitle)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                // The whole height stays tappable, but the row keeps the icon's height.
                .padding(.vertical, (Self.iconSize - PaeoniaSpacing.compactButtonHeight) / 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.mail.mailbox")
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
            mailboxButton
        }
    }

    private func row(waiting: [Letter]) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: PaeoniaSpacing.space16))
        let width = min(artWidth, 120)
        return layout {
            MailSealedEnvelope(width: width)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(title(waiting: waiting.count))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(.mailCardWaitingMessage)
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
        count == 1 ? .mailCardWaitingOne(partnerName) : .mailCardWaitingMany(count, partnerName)
    }
}
