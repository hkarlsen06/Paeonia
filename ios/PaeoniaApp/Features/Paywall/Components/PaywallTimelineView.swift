import SwiftUI

struct PaywallTimelineItem: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let systemImage: String
    let isActive: Bool
}

struct PaywallTimelineView: View {
    let items: [PaywallTimelineItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                PaywallTimelineRow(
                    item: item,
                    isLast: index == items.count - 1
                )
            }
        }
        .padding(.top, PaeoniaSpacing.space2)
    }
}

private struct PaywallTimelineRow: View {
    let item: PaywallTimelineItem
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(item.isActive ? Color.paeoniaAccentPrimary : Color.paeoniaSurfaceSecondary)
                        .frame(width: 42, height: 42)

                    Image(systemName: item.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(item.isActive ? .paeoniaTextInverse : .paeoniaTextTertiary)
                }

                if !isLast {
                    Rectangle()
                        .fill(item.isActive ? Color.paeoniaAccentPrimary.opacity(0.72) : Color.paeoniaSurfaceSecondary)
                        .frame(width: 3, height: 38)
                }
            }
            .frame(width: 46)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(item.title)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(item.message)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, PaeoniaSpacing.space4)

            Spacer(minLength: 0)
        }
    }
}
