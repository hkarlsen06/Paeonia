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
    @State private var dataExport: DataExportViewModel
    @State private var isShowingCorrectionRequest = false
    /// Missing in previews and tests, which then hide the usage switch.
    @Environment(UsageSharingModel.self) private var usageSharing: UsageSharingModel?
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @MainActor
    init(
        partnerUserID: UUID?,
        partnerName: String,
        service: (any PrivacySafetyServicing)? = PrivacySafetyServiceFactory.makeDefault(),
        dataExportService: (any DataExportServicing)? = DataExportServiceFactory.makeDefault(),
        operationProvider: (any SyncClientOperationProviding)? = nil,
        onReportedAndLeft: @escaping () -> Void = {}
    ) {
        self.partnerUserID = partnerUserID
        self.partnerName = partnerName
        self.service = service
        self.operationProvider = operationProvider
        self.onReportedAndLeft = onReportedAndLeft
        _viewModel = State(initialValue: PrivacySafetyViewModel(service: service))
        _dataExport = State(initialValue: DataExportViewModel(service: dataExportService))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                Text(introduction)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                privacyRequestsSection

                if let usageSharing, PaeoniaAnalytics.isAvailable, usageSharing.userID != nil {
                    usageSection(usageSharing)
                }

                if let partnerUserID {
                    safetySection(partnerUserID: partnerUserID)
                }
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space40)
            .paeoniaReadableWidth(alignment: .leading)
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
                    DataExportSection(viewModel: dataExport)

                    Divider()
                        .overlay(.paeoniaSurfacePressed)

                    PrivacyRequestRow(
                        kind: .correction,
                        latestRequest: viewModel.latestRequest(for: .correction),
                        isLoading: !viewModel.hasLoaded,
                        isSubmitting: viewModel.isSubmitting(.correction)
                    ) {
                        isShowingCorrectionRequest = true
                    }
                }
            }
        }
    }

    private func usageSection(_ usageSharing: UsageSharingModel) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            sectionHeader(.privacySafetyUsageSectionTitle)

            PaeoniaCard {
                Toggle(isOn: Binding(
                    get: { usageSharing.shares == true },
                    set: { shares in Task { await usageSharing.answer(shares) } }
                )) {
                    Text(.privacySafetyUsageToggleTitle)
                    Text(.privacySafetyUsageToggleDescription)
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
        case let .requestFailed(failure):
            // Only a phone without a connection is told to check it.
            bannerCenter.show(
                .error(
                    title: String(localized: .privacySafetyRequestFailedTitle),
                    message: String(localized: failure == .offline
                        ? .privacySafetyRequestFailedMessage : .commonActionFailedMessage),
                    timing: .untilDismissed
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
            service: nil,
            dataExportService: nil
        )
    }
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
