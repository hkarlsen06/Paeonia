import SwiftUI

struct PrivacySafetyView: View {
    /// Nil when the user has no partner. Data requests still work, and the
    /// report section is hidden.
    let partnerUserID: UUID?
    let partnerName: String
    let onReportedAndLeft: () -> Void

    private let service: (any PrivacySafetyServicing)?
    private let operationProvider: (any SyncClientOperationProviding)?
    @State private var viewModel: PrivacySafetyViewModel
    @State private var isShowingCorrectionRequest = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @MainActor
    init(
        partnerUserID: UUID?,
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
                Text(introduction)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                privacyRequestsSection

                if let partnerUserID {
                    safetySection(partnerUserID: partnerUserID)
                }
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
        .task {
            await viewModel.observe()
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

    private var introduction: LocalizedStringResource {
        partnerUserID == nil ? .privacySafetyIntroductionDataOnly : .privacySafetyIntroduction
    }

    private var privacyRequestsSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            sectionHeader(.privacySafetyRequestsSectionTitle)

            PaeoniaCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(PrivacyRequestKind.allCases, id: \.self) { kind in
                        if kind != PrivacyRequestKind.allCases.first {
                            Divider()
                                .overlay(.paeoniaSurfacePressed)
                        }

                        PrivacyRequestRow(
                            kind: kind,
                            latestRequest: viewModel.latestRequest(for: kind),
                            isLoading: !viewModel.hasLoaded,
                            isSubmitting: viewModel.isSubmitting(kind)
                        ) {
                            request(kind)
                        }
                    }
                }
            }
        }
    }

    private func safetySection(partnerUserID: UUID) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            sectionHeader(.privacySafetySafetySectionTitle)

            PaeoniaCard(padding: 0) {
                NavigationLink {
                    ReportAndLeaveView(
                        partnerUserID: partnerUserID,
                        partnerName: partnerName,
                        service: service,
                        operationProvider: operationProvider,
                        onReportedAndLeft: onReportedAndLeft
                    )
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

    private func request(_ kind: PrivacyRequestKind) {
        if kind == .correction {
            isShowingCorrectionRequest = true
        } else {
            Task {
                await viewModel.submitRequest(kind: kind)
            }
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
