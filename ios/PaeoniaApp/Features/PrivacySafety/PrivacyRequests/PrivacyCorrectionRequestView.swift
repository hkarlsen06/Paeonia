import SwiftUI

/// The sheet covers the app's root banner, so it mounts the shared banner itself.
/// `PrivacySafetyView` still turns the view model's notices into banners. A failed
/// send keeps the typed text and leaves the sheet open.
struct PrivacyCorrectionRequestView: View {
    @Bindable var viewModel: PrivacySafetyViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    private var isSubmitting: Bool {
        viewModel.isSubmitting(.correction)
    }

    var body: some View {
        NavigationStack {
            correctionContent
        }
        .paeoniaTopBanner(bannerCenter)
        .presentationDetents([.large])
        .presentationBackground(.paeoniaBackgroundPrimary)
        .interactiveDismissDisabled(isSubmitting)
    }

    private var correctionContent: some View {
        ScrollView {
            formContent
        }
        .scrollBounceBehavior(.basedOnSize)
        .paeoniaScreenBackground()
        .scrollDismissesKeyboard(.interactively)
        .paeoniaBottomBar {
            submitButton
        }
        .navigationTitle(Text(.privacySafetyCorrectionFormTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    viewModel.correctionDraft = ""
                    dismiss()
                } label: {
                    Text(.commonCancel)
                }
                .disabled(isSubmitting)
                .accessibilityIdentifier("privacy.correction.cancel")
            }
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
            Text(.privacySafetyCorrectionFormDescription)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            detailsField
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.screenTopSpacing)
        .padding(.bottom, PaeoniaSpacing.space24)
    }

    private var detailsField: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.privacySafetyCorrectionDetailsLabel)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityHidden(true)

            PrivacySafetyMultilineField(
                text: $viewModel.correctionDraft,
                label: .privacySafetyCorrectionDetailsLabel,
                placeholder: .privacySafetyCorrectionDetailsPlaceholder,
                lineLimit: 4...9
            )
            .accessibilityIdentifier("privacy.correction.details")
            .disabled(isSubmitting)
        }
    }

    private var submitButton: some View {
        Button {
            Task {
                if await viewModel.submitRequest(
                    kind: .correction,
                    requesterNote: viewModel.correctionDraft
                ) {
                    viewModel.correctionDraft = ""
                    dismiss()
                }
            }
        } label: {
            Text(submitButtonTitle)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!viewModel.canSubmitCorrection(details: viewModel.correctionDraft))
        .accessibilityIdentifier("privacy.correction.submit")
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(.paeoniaBackgroundPrimary)
    }

    private var submitButtonTitle: LocalizedStringResource {
        isSubmitting ? .privacySafetyRequestSending : .privacySafetyCorrectionSubmit
    }
}
