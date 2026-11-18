import SwiftUI

/// Asks for a yes before a person answers a private topic such as Flirt, whose
/// answers are more intimate than the rest of the app. The first time they open
/// the topic it shows this, and so does the switch in Privacy and safety. Both
/// answers look the same and are equally easy to pick, because the law asks for a
/// free choice. A yes is saved on the server before the sheet closes, since the
/// server refuses an answer there without it. The sheet is not counted as a screen
/// in usage statistics, which would say who looked at Flirt.
struct PrivateTopicConsentSheet: View {
    enum Purpose {
        /// A yes opens the topic.
        case openTopic
        /// A yes from Privacy and safety, where nothing opens afterwards.
        case turnOn
    }

    let topicKey: String
    let topicName: String
    var purpose = Purpose.openTopic
    let viewModel: TopicsViewModel
    /// The server has the yes.
    let onConsented: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        GeometryReader { proxy in
            content(minHeight: proxy.size.height)
        }
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(viewModel.isSavingPrivateTopicsConsent)
        .paeoniaBanner(bannerCenter)
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
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space24)
            .frame(minHeight: minHeight)
            .paeoniaReadableWidth()
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var message: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            TopicArtwork(topicKey: topicKey, height: 112)
                .frame(height: 124)
                .accessibilityHidden(true)

            VStack(spacing: PaeoniaSpacing.space12) {
                Text(.topicsPrivateConsentTitle(topicName))
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(.topicsPrivateConsentMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)

                Text(.topicsPrivateConsentFootnote(topicName))
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
                Task { await sayYes() }
            } label: {
                Text(yesTitle)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: viewModel.isSavingPrivateTopicsConsent))
            .accessibilityIdentifier("topics.privateConsent.yes")

            Button {
                dismiss()
            } label: {
                Text(.topicsPrivateConsentNotNow)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .accessibilityIdentifier("topics.privateConsent.notNow")
        }
        .disabled(viewModel.isSavingPrivateTopicsConsent)
    }

    private var yesTitle: LocalizedStringResource {
        switch purpose {
        case .openTopic:
            .topicsPrivateConsentYes(topicName)
        case .turnOn:
            .topicsPrivateConsentYesTurnOn(topicName)
        }
    }

    private func sayYes() async {
        if let failure = await viewModel.setPrivateTopicsConsent(true) {
            bannerCenter.show(failure.topicsBanner)
        } else {
            onConsented()
        }
    }
}
