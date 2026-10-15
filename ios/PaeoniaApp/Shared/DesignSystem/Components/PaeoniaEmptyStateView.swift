import SwiftUI

struct PaeoniaEmptyStateView<Action: View>: View {
    private let title: LocalizedStringResource
    private let message: LocalizedStringResource
    private let systemImage: String?
    private let illustration: ImageResource?
    private let action: Action

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 32
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var illustrationSettled = false

    /// The width of an illustration. The art is imported for about this size.
    private var illustrationWidth: CGFloat { 150 }

    init(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        systemImage: String? = nil,
        illustration: ImageResource? = nil,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.illustration = illustration
        self.action = action()
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            image

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(title)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)

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
        if let illustration {
            // Settles in once: it rises a little and grows to full size on a soft spring.
            Image(illustration)
                .resizable()
                .scaledToFit()
                .frame(width: illustrationWidth)
                .scaleEffect(illustrationSettled ? 1 : 0.88)
                .offset(y: illustrationSettled ? 0 : 14)
                .opacity(illustrationSettled ? 1 : 0)
                .onAppear {
                    if reduceMotion {
                        illustrationSettled = true
                    } else {
                        withAnimation(.spring(duration: 0.7, bounce: 0.25)) {
                            illustrationSettled = true
                        }
                    }
                }
                .accessibilityHidden(true)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
        }
    }
}

extension PaeoniaEmptyStateView where Action == EmptyView {
    init(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        systemImage: String? = nil,
        illustration: ImageResource? = nil
    ) {
        self.init(title: title, message: message, systemImage: systemImage, illustration: illustration) {
            EmptyView()
        }
    }
}
