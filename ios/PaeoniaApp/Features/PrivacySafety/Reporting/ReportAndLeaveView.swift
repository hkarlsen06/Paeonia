import SwiftUI

struct ReportAndLeaveView: View {
    let partnerUserID: UUID
    let partnerName: String
    let onReportedAndLeft: () -> Void

    private let reportTarget: PrivacyReportTarget

    @State private var viewModel: ReportAndLeaveViewModel
    @State private var isConfirmingSubmission = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @MainActor
    init(
        partnerUserID: UUID,
        partnerName: String,
        reportTarget: PrivacyReportTarget? = nil,
        service: (any PrivacySafetyServicing)? = PrivacySafetyServiceFactory.makeDefault(),
        operationProvider: (any SyncClientOperationProviding)? = nil,
        onReportedAndLeft: @escaping () -> Void = {}
    ) {
        self.partnerUserID = partnerUserID
        self.partnerName = partnerName
        self.reportTarget = reportTarget ?? .conduct(userID: partnerUserID)
        self.onReportedAndLeft = onReportedAndLeft
        _viewModel = State(
            initialValue: ReportAndLeaveViewModel(
                service: service,
                operationProvider: operationProvider
            )
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                Text(.reportAndLeaveIntroduction(partnerName))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                reportDetailsCard(
                    selectedReason: $viewModel.selectedReason,
                    note: $viewModel.note
                )
                blockCard(blockPartner: $viewModel.blockPartner)

                Button {
                    if viewModel.prepareConfirmation() {
                        isConfirmingSubmission = true
                    }
                } label: {
                    Label {
                        Text(submitButtonTitle)
                    } icon: {
                        Image(systemName: "heart.slash.fill")
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(PaeoniaDestructiveButtonStyle())
                .disabled(viewModel.isSubmitting)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.reportAndLeaveTitle))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else {
                return
            }
            handleNotice(notice)
            viewModel.dismissNotice()
        }
        .alert(
            Text(.reportAndLeaveConfirmTitle(partnerName)),
            isPresented: $isConfirmingSubmission
        ) {
            Button(role: .destructive) {
                Task {
                    await viewModel.submit(target: reportTarget)
                }
            } label: {
                Text(.reportAndLeaveConfirmAction)
            }

            Button(role: .cancel, action: {}) {
                Text(.reportAndLeaveConfirmCancel)
            }
        } message: {
            Text(confirmMessage)
        }
    }

    private func reportDetailsCard(
        selectedReason: Binding<PrivacyReportReason?>,
        note: Binding<String>
    ) -> some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                reportReasonField(selectedReason: selectedReason)

                Divider()
                    .overlay(.paeoniaSurfacePressed)

                reportNoteField(note: note)
            }
        }
    }

    private func reportReasonField(
        selectedReason: Binding<PrivacyReportReason?>
    ) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.reportAndLeaveReasonLabel)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)

            Picker(
                selection: selectedReason,
                label: Text(.reportAndLeaveReasonLabel)
            ) {
                Text(.reportAndLeaveReasonPlaceholder)
                    .tag(Optional<PrivacyReportReason>.none)

                ForEach(PrivacyReportReason.allCases, id: \.self) { reason in
                    Text(reason.title)
                        .tag(Optional(reason))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.paeoniaAccentPrimary)
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight, alignment: .leading)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .background(.paeoniaSurfaceSecondary)
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                    .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
            }
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
        }
    }

    private func reportNoteField(note: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.reportAndLeaveNoteLabel)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)

            Text(.reportAndLeaveNoteDescription)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            PrivacySafetyMultilineField(
                text: note,
                placeholder: .reportAndLeaveNotePlaceholder
            )
            .onChange(of: note.wrappedValue) { _, newValue in
                if newValue.count > 4_000 {
                    note.wrappedValue = String(newValue.prefix(4_000))
                }
            }
        }
    }

    private func blockCard(blockPartner: Binding<Bool>) -> some View {
        PaeoniaCard {
            Toggle(isOn: blockPartner) {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    Text(.reportAndLeaveBlockTitle(partnerName))
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)

                    Text(.reportAndLeaveBlockDescription(partnerName))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(.paeoniaError)
        }
    }

    private var confirmMessage: LocalizedStringResource {
        if viewModel.blockPartner {
            return .reportAndLeaveConfirmBlockMessage(partnerName)
        }
        return .reportAndLeaveConfirmMessage(partnerName)
    }

    private var submitButtonTitle: LocalizedStringResource {
        viewModel.isSubmitting
            ? .reportAndLeaveSubmitting
            : .reportAndLeaveSubmitButton(partnerName)
    }

    private func handleNotice(_ notice: ReportAndLeaveViewModel.Notice) {
        switch notice {
        case .reasonRequired:
            bannerCenter.show(
                .error(
                    title: String(localized: .reportAndLeaveReasonRequiredTitle),
                    message: String(localized: .reportAndLeaveReasonRequiredMessage)
                )
            )
        case .submitFailed:
            bannerCenter.show(
                .error(
                    title: String(localized: .reportAndLeaveFailedTitle),
                    message: String(localized: .reportAndLeaveFailedMessage)
                )
            )
        case .submitted:
            bannerCenter.show(
                .info(
                    title: String(localized: .reportAndLeaveSubmittedTitle),
                    message: String(localized: .reportAndLeaveSubmittedMessage)
                )
            )
            onReportedAndLeft()
        }
    }
}

#Preview {
    NavigationStack {
        ReportAndLeaveView(
            partnerUserID: UUID(),
            partnerName: "Oda",
            service: nil
        )
    }
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
