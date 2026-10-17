import SwiftUI

/// Asks whether the person shares usage statistics and crash reports. It is the
/// last page of profile setup, and a sheet for an account that never saw that
/// page. Nothing is sent before they answer. Both answers look the same and are
/// equally easy to pick, because the law asks for a free choice.
struct UsageSharingQuestionView: View {
    let onAnswer: (Bool) -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 46

    var body: some View {
        GeometryReader { proxy in
            content(minHeight: proxy.size.height)
        }
    }

    private func content(minHeight: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space24) {
                Spacer(minLength: PaeoniaSpacing.space24)
                message
                Spacer(minLength: PaeoniaSpacing.space32)
                actions
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PaeoniaSpacing.space24)
            .frame(minHeight: minHeight)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var message: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            VStack(spacing: PaeoniaSpacing.space12) {
                Text(.usageSharingQuestionTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(.usageSharingQuestionMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)

                Text(.usageSharingQuestionFootnote)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Button {
                onAnswer(true)
            } label: {
                Text(.usageSharingQuestionYes)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())

            Button {
                onAnswer(false)
            } label: {
                Text(.usageSharingQuestionNo)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
        }
    }
}

#if DEBUG
#Preview {
    Color.paeoniaBackgroundPrimary
        .sheet(isPresented: .constant(true)) {
            UsageSharingQuestionView { _ in }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .background(.paeoniaBackgroundPrimary)
        }
        .preferredColorScheme(.dark)
}
#endif
