import SwiftUI

/// The heart row on the compact Home card, for couples who have no map. Both
/// avatars sit with a heart between them. A tap sends a heart, and the partner's
/// hearts fly back to the person's avatar here.
struct MapHeartsButton: View {
    let currentName: String
    let currentProfilePhotoAssetID: UUID?
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    let incomingBurst: HeartsBurst?
    let onSend: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flights = HeartFlights()
    @State private var tapCount = 0

    private static let avatarDiameter: CGFloat = 28
    private static let heartGap: CGFloat = 36
    private static let width = avatarDiameter * 2 + heartGap

    var body: some View {
        Button {
            tapCount += 1
            flights.send()
            onSend()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .onChange(of: incomingBurst) { _, burst in
            if let burst {
                flights.receive(count: burst.flyingCount)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.heartsSendAction))
        .accessibilityHint(Text(.heartsSendHint(partnerName)))
    }

    private var label: some View {
        HStack(spacing: Self.heartGap) {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: currentProfilePhotoAssetID,
                name: currentName,
                tint: .paeoniaPartnerOne,
                size: Self.avatarDiameter
            )
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: partnerProfilePhotoAssetID,
                name: partnerName,
                tint: .paeoniaPartnerTwo,
                size: Self.avatarDiameter
            )
        }
        .overlay {
            Image(systemName: "heart.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.paeoniaAccentSecondary)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : tapCount)
                .accessibilityHidden(true)
        }
        .frame(width: Self.width, height: PaeoniaSpacing.compactButtonHeight)
        .contentShape(Rectangle())
        // Hearts fly over the whole button, and past its edge on a wide arc.
        .overlay {
            KissLayer(
                start: CGPoint(x: Self.avatarDiameter / 2, y: PaeoniaSpacing.compactButtonHeight / 2),
                end: CGPoint(x: Self.width - Self.avatarDiameter / 2, y: PaeoniaSpacing.compactButtonHeight / 2),
                tapKisses: flights.kisses,
                showsAmbient: false
            )
        }
    }
}

/// "Robin sent you 14 hearts" while the partner's hearts play.
struct HeartsIncomingLine: View {
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: "heart.fill")
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .foregroundStyle(.paeoniaAccentPrimary)
    }
}
