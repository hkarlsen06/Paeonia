import SwiftUI

struct PrivacySafetyView: View {
    let partnerUserID: UUID
    let partnerName: String
    let onReportedAndLeft: () -> Void

    private let service: (any PrivacySafetyServicing)?
    private let operationProvider: (any SyncClientOperationProviding)?
    @State private var viewModel: PrivacySafetyViewModel
    @State private var isShowingCorrectionRequest = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @MainActor
    init(
        partnerUserID: UUID,
        partnerName: String,
        service: (any PrivacySafetyServicing)? = PrivacySafetyServiceFactory.makeDefault(),
        operationProvider: (any SyncClientOperationProviding)? = nil,
        onReportedAndLeft: @escaping () -> Void = {}
    ) {
        self.partnerUserID = partnerUserID
        self.partnerName = partnerName
        self.service = service
        self.operationProvider = operationProvider
        self.onReportedAndLeft = onReportedAndLeft
        _viewModel = State(initialValue: PrivacySafetyViewModel(service: service))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                Text(.privacySafetyIntroduction)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                privacyRequestsSection
                safetySection
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.privacySafetyTitle))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else {
                return
            }
            showBanner(for: notice)
            viewModel.dismissNotice()
        }
        .sheet(isPresented: $isShowingCorrectionRequest) {
            PrivacyCorrectionRequestView(viewModel: viewModel)
        }
    }

    private var privacyRequestsSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            sectionHeader(.privacySafetyRequestsSectionTitle)

            PaeoniaCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(PrivacyRequestKind.allCases, id: \.self) { kind in
                        requestRow(kind)

                        if kind != .correction {
                            Divider()
                                .overlay(.paeoniaSurfacePressed)
                        }
                    }
                }
            }
        }
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            sectionHeader(.privacySafetySafetySectionTitle)

            PaeoniaCard(padding: 0) {
                NavigationLink {
                    reportDestination
                } label: {
                    PaeoniaDisclosureRow(
                        title: .privacySafetyReportTitle(partnerName),
                        message: .privacySafetyReportDescription(partnerName),
                        systemImage: "exclamationmark.shield",
                        iconTint: .paeoniaError
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reportDestination: some View {
        ReportAndLeaveView(
            partnerUserID: partnerUserID,
            partnerName: partnerName,
            service: service,
            operationProvider: operationProvider,
            onReportedAndLeft: onReportedAndLeft
        )
    }

    private func requestRow(_ kind: PrivacyRequestKind) -> some View {
        let latestRequest = viewModel.latestRequest(for: kind)
        let isSubmitting = viewModel.isSubmitting(kind)
        let isActive = latestRequest?.isActive == true

        return VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(kind.title)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(kind.description)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let latestRequest {
                requestStatus(latestRequest)
            }

            Button {
                if kind == .correction {
                    isShowingCorrectionRequest = true
                } else {
                    Task {
                        await viewModel.submitRequest(kind: kind)
                    }
                }
            } label: {
                Text(requestButtonTitle(kind: kind, isSubmitting: isSubmitting, isActive: isActive))
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .disabled(isSubmitting || isActive)
        }
        .padding(PaeoniaSpacing.space16)
    }

    private func requestStatus(_ request: PrivacyRequest) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Label {
                Text(request.status.title)
            } icon: {
                Image(systemName: requestStatusIcon(request.status))
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption)
            .foregroundStyle(requestStatusColor(request.status))

            if let message = request.visibleStatusMessage?.nilIfBlank {
                Text(verbatim: message)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requestButtonTitle(
        kind: PrivacyRequestKind,
        isSubmitting: Bool,
        isActive: Bool
    ) -> LocalizedStringResource {
        if isSubmitting {
            return .privacySafetyRequestSending
        }
        if isActive {
            return .privacySafetyRequestActive
        }
        return kind.actionTitle
    }

    private func requestStatusIcon(_ status: PrivacyRequestStatus) -> String {
        switch status {
        case .submitted, .verifying, .processing:
            "clock"
        case .completed:
            "checkmark.circle"
        case .rejected, .cancelled:
            "xmark.circle"
        }
    }

    private func requestStatusColor(_ status: PrivacyRequestStatus) -> Color {
        switch status {
        case .submitted, .verifying, .processing:
            .paeoniaAccentPrimary
        case .completed:
            .paeoniaSuccess
        case .rejected, .cancelled:
            .paeoniaTextTertiary
        }
    }

    private func sectionHeader(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(PaeoniaTypography.sectionTitle)
            .foregroundStyle(.paeoniaTextSecondary)
    }

    private func showBanner(for notice: PrivacySafetyViewModel.Notice) {
        switch notice {
        case .loadFailed:
            bannerCenter.show(
                .error(
                    title: String(localized: .privacySafetyLoadFailedTitle),
                    message: String(localized: .privacySafetyLoadFailedMessage)
                )
            )
        case .requestSubmitted:
            bannerCenter.show(
                .info(
                    title: String(localized: .privacySafetyRequestSubmittedTitle),
                    message: String(localized: .privacySafetyRequestSubmittedMessage)
                )
            )
        case .requestAlreadyActive:
            bannerCenter.show(
                .info(
                    title: String(localized: .privacySafetyRequestActiveTitle),
                    message: String(localized: .privacySafetyRequestActiveMessage)
                )
            )
        case .requestFailed:
            bannerCenter.show(
                .error(
                    title: String(localized: .privacySafetyRequestFailedTitle),
                    message: String(localized: .privacySafetyRequestFailedMessage)
                )
            )
        case .correctionDetailsRequired:
            bannerCenter.show(
                .error(
                    title: String(localized: .privacySafetyCorrectionDetailsRequiredTitle),
                    message: String(localized: .privacySafetyCorrectionDetailsRequiredMessage)
                )
            )
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    NavigationStack {
        PrivacySafetyView(
            partnerUserID: UUID(),
            partnerName: "Oda",
            service: nil
        )
    }
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
