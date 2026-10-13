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
                .disabled(!viewModel.canSubmit)
            }
            .disabled(viewModel.isFormLocked)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space40)
            .paeoniaReadableWidth(alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .paeoniaScreenBackground()
        .navigationTitle(Text(.reportAndLeaveTitle))
        .navigationBarTitleDisplayMode(.inline)
        // Going back mid-send would leave the app unaware that the relationship
        // ended. This also turns off the swipe-back gesture.
        .navigationBarBackButtonHidden(viewModel.isSubmitting)
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else {
                return
            }
            showBanner(for: notice)
            viewModel.dismissNotice()
        }
        .alert(
            Text(.reportAndLeaveConfirmTitle(partnerName)),
            isPresented: $isConfirmingSubmission
        ) {
            Button(role: .destructive) {
                submit()
            } label: {
                Text(.reportAndLeaveConfirmAction)
            }

            Button(role: .cancel, action: {}) {
                Text(.commonCancel)
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
                ReportReasonField(selection: selectedReason)

                Divider()
                    .overlay(.paeoniaSurfacePressed)

                reportNoteField(note: note)
            }
        }
    }

    private func reportNoteField(note: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.reportAndLeaveNoteLabel)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityHidden(true)

            Text(.reportAndLeaveNoteDescription)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            PrivacySafetyMultilineField(
                text: note,
                label: .reportAndLeaveNoteLabel,
                placeholder: .reportAndLeaveNotePlaceholder
            )
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

    /// Reports success from the same task that sent the report, so the app still
    /// learns that the relationship ended if this screen is gone by then. The task
    /// takes its own copies of everything it uses for that reason.
    private func submit() {
        let viewModel = self.viewModel
        let target = reportTarget
        let bannerCenter = self.bannerCenter
        let onReportedAndLeft = self.onReportedAndLeft

        Task {
            guard await viewModel.submit(target: target) else {
                return
            }
            bannerCenter.show(
                .info(
                    title: String(localized: .reportAndLeaveSubmittedTitle),
                    message: String(localized: .reportAndLeaveSubmittedMessage)
                )
            )
            onReportedAndLeft()
        }
    }

    private func showBanner(for notice: ReportAndLeaveViewModel.Notice) {
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
