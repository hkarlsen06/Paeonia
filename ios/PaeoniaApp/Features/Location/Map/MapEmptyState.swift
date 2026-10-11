import SwiftUI

/// The content of the map tile when there is no map to show: an icon, a short
/// explanation, and either one action button or a spinner.
struct MapEmptyState: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let systemImage: String
    var actionTitle: LocalizedStringResource?
    var actionSystemImage: String?
    var action: (() -> Void)?
    /// Shows a spinner where the action button would be.
    var showsProgress = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            Color.paeoniaBackgroundSecondary

            VStack(spacing: PaeoniaSpacing.space8) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)

                textBlock

                actionBlock
            }
            .padding(PaeoniaSpacing.space12)
        }
    }

    private var textBlock: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(title)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .multilineTextAlignment(.center)

            Text(message)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var actionBlock: some View {
        if showsProgress {
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(minHeight: PaeoniaSpacing.buttonHeight)
        } else if let actionTitle, let action {
            actionButton(title: actionTitle, action: action)
        }
    }

    private func actionButton(title: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .multilineTextAlignment(.center)
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
        .frame(minHeight: PaeoniaSpacing.buttonHeight)
        .background(.paeoniaAccentPrimary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .buttonStyle(.plain)
    }
}
