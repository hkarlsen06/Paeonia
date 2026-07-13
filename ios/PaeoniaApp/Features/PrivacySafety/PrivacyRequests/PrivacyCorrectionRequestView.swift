import SwiftUI

struct PrivacyCorrectionRequestView: View {
    let viewModel: PrivacySafetyViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var details = ""

    var body: some View {
        NavigationStack {
            correctionContent
        }
        .presentationDetents([.medium, .large])
    }

    private var correctionContent: some View {
        ScrollView {
            formContent
        }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.privacySafetyCorrectionFormTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text(.commonCancel)
                }
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
            submitButton
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.screenTopSpacing)
        .padding(.bottom, PaeoniaSpacing.space40)
    }

    private var detailsField: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.privacySafetyCorrectionDetailsLabel)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)

            PrivacySafetyMultilineField(
                text: $details,
                placeholder: .privacySafetyCorrectionDetailsPlaceholder,
                lineLimit: 4...9
            )
            .onChange(of: details) { _, newValue in
                if newValue.count > 4_000 {
                    details = String(newValue.prefix(4_000))
                }
            }
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
        .disabled(viewModel.isSubmitting(.correction))
    }

    private var submitButtonTitle: LocalizedStringResource {
        viewModel.isSubmitting(.correction)
            ? .privacySafetyRequestSending
            : .privacySafetyCorrectionSubmit
    }
}
