import SwiftUI
import UIKit

/// The reports and correction requests nobody has handled yet, the one that has waited longest
/// first. A row opens the person it is about, where an admin can ban them.
struct AdminOpenCasesView: View {
    private let gateway: any AdminGateway
    @State private var viewModel: AdminOpenCasesViewModel
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @MainActor
    init(gateway: any AdminGateway) {
        self.gateway = gateway
        _viewModel = State(initialValue: AdminOpenCasesViewModel(gateway: gateway))
    }

    var body: some View {
        List {
            Group {
                if !viewModel.reports.isEmpty {
                    reportsSection
                }
                if !viewModel.correctionRequests.isEmpty {
                    correctionRequestsSection
                }
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .listStyle(.insetGrouped)
        .paeoniaGroupedList()
        .overlay { overlay }
        .navigationTitle(Text(.adminHubOpenCases))
        .navigationBarTitleDisplayMode(.inline)
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
            bannerCenter.show(notice.banner)
            viewModel.dismissNotice()
        }
    }

    private var reportsSection: some View {
        Section {
            ForEach(viewModel.reports) { report in
                NavigationLink {
                    userDetail(report.reportedUserID)
                } label: {
                    AdminOpenReportRow(report: report)
                }
                .contextMenu {
                    // The moderation commands take the report's id.
                    Button {
                        UIPasteboard.general.string = report.id.uuidString.lowercased()
                    } label: {
                        Label {
                            Text(.adminCasesCopyReportID)
                        } icon: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
            }
        } header: {
            Text(.adminCasesReportsSection)
        }
    }

    private var correctionRequestsSection: some View {
        Section {
            ForEach(viewModel.correctionRequests) { request in
                NavigationLink {
                    userDetail(request.userID)
                } label: {
                    AdminCorrectionRequestRow(request: request)
                }
            }
        } header: {
            Text(.adminCasesCorrectionsSection)
        }
    }

    private func userDetail(_ userID: UUID) -> some View {
        AdminUserDetailView(
            userID: userID,
            gateway: gateway,
            onChanged: { [viewModel] in await viewModel.load() }
        )
    }

    @ViewBuilder
    private var overlay: some View {
        if !viewModel.hasLoaded, let failure = viewModel.loadFailure {
            PaeoniaLoadFailureView(failure: failure, offlineMessage: .commonLoadOfflineMessage) {
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
            .padding(PaeoniaSpacing.screenHorizontalPadding)
        } else if !viewModel.hasLoaded {
            ProgressView()
        } else if viewModel.isEmpty {
            PaeoniaEmptyStateView(
                title: .adminCasesEmptyTitle,
                message: .adminCasesEmptyMessage,
                systemImage: "checkmark.bubble"
            )
        }
    }
}
