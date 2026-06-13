import SwiftUI

struct PaeoniaEmptyStateView<Action: View>: View {
    private let title: LocalizedStringResource
    private let message: LocalizedStringResource
    private let systemImage: String?
    private let action: Action

    init(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        systemImage: String? = nil,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action()
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            image

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(title)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(message)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .multilineTextAlignment(.center)

            action
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PaeoniaSpacing.space8)
    }

    @ViewBuilder
    private var image: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
        }
    }
}

extension PaeoniaEmptyStateView where Action == EmptyView {
    init(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        systemImage: String? = nil
    ) {
        self.init(title: title, message: message, systemImage: systemImage) {
            EmptyView()
        }
    }
}
