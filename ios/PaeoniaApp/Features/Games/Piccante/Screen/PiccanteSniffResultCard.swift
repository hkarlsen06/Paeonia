import SwiftUI

struct PiccanteSniffResultCard: View {
    let sniff: PiccanteSniff
    let partnerName: String
    @ScaledMetric(relativeTo: .title2) private var iconSide: CGFloat = 56
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space16))
        layout {
            Image(systemName: sniff.hasChili ? "flame.fill" : "checkmark")
                .font(.system(size: iconSide * 0.46, weight: .bold))
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(width: iconSide, height: iconSide)
                .background(sniff.hasChili ? Color.paeoniaWarning : .paeoniaSurfaceSecondary, in: Circle())
                .overlay { Circle().strokeBorder(Color.paeoniaTextPrimary, lineWidth: 2) }
                .shadow(color: .paeoniaWarning.opacity(sniff.hasChili ? 0.8 : 0), radius: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(sniff.hasChili ? .piccanteSniffHotTitle(partnerName) : .piccanteSniffSafeTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(sniff.hasChili ? .piccanteSniffHotMessage : .piccanteSniffSafeMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(PaeoniaSpacing.space20)
        .paeoniaCardSurface(
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius20),
            fill: sniff.hasChili ? Color.paeoniaWarning.opacity(0.18) : Color.paeoniaSurfacePrimary
        )
        .overlay {
            if sniff.hasChili {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius20)
                    .strokeBorder(Color.paeoniaWarning, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("piccante.sniff.answer")
    }
}
