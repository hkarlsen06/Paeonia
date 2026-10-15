import SwiftUI

/// The compact card shown on the Home tab when there is no map: an icon, a short
/// explanation, and either one action button or a spinner. The icon leads, the text
/// fills the rest with the action button under it, and a spinner trails. At
/// accessibility text sizes the icon moves above the text. Couples who are paired
/// also get the heart row (`MapHeartsButton`) at the trailing edge, and a line above
/// the title while the partner's hearts play. The avatars and heart already make the
/// row read as "the two of you", so the icon is left out when the heart row shows.
/// `CoupleMapCard` adds the rounded frame, stroke, and shadow around it.
struct MapEmptyState: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let systemImage: String
    var actionTitle: LocalizedStringResource?
    var actionSystemImage: String?
    var action: (() -> Void)?
    /// Shows a spinner where the action button would be.
    var showsProgress = false
    var hearts: MapHeartsButton?
    /// "Robin sent you 14 hearts" while the partner's hearts play.
    var incomingLine: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        layout {
            if hearts == nil {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }

            textBlock

            if showsProgress {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
            }

            if let hearts {
                hearts
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: incomingLine)
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.paeoniaBackgroundSecondary)
    }

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: PaeoniaSpacing.space12))
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            if let incomingLine {
                HeartsIncomingLine(text: incomingLine)
                    .transition(.opacity)
            }

            Text(title)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)

            Text(message)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)

            // Under the text rather than trailing, so the message keeps the full
            // width on a narrow phone.
            if !showsProgress, let actionTitle, let action {
                actionButton(title: actionTitle, action: action)
                    .padding(.top, PaeoniaSpacing.space8)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(title: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .multilineTextAlignment(.leading)
            } icon: {
                if let actionSystemImage {
                    Image(systemName: actionSystemImage)
                        .accessibilityHidden(true)
                }
            }
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .foregroundStyle(.paeoniaTextInverse)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
        .background(.paeoniaAccentPrimary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .buttonStyle(.plain)
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
    }
}
