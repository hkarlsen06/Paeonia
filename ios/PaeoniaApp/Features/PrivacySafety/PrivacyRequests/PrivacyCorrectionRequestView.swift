import SwiftUI

/// The sheet covers the app's root banner, so it mounts the shared banner itself.
/// `PrivacySafetyView` still turns the view model's notices into banners. A failed
/// send keeps the typed text and leaves the sheet open.
struct PrivacyCorrectionRequestView: View {
    let viewModel: PrivacySafetyViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var details = ""

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
                    dismiss()
                } label: {
                    Text(.commonCancel)
                }
                .disabled(isSubmitting)
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
                text: $details,
                label: .privacySafetyCorrectionDetailsLabel,
                placeholder: .privacySafetyCorrectionDetailsPlaceholder,
                lineLimit: 4...9
            )
        }
    }

    private var submitButton: some View {
        Button {
            Task {
                if await viewModel.submitRequest(
                    kind: .correction,
                    requesterNote: details
                ) {
                    dismiss()
                }
            }
        } label: {
            Text(submitButtonTitle)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!viewModel.canSubmitCorrection(details: details))
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(.paeoniaBackgroundPrimary)
    }

    private var submitButtonTitle: LocalizedStringResource {
        isSubmitting ? .privacySafetyRequestSending : .privacySafetyCorrectionSubmit
    }
}
