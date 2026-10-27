import SwiftUI

/// The "Download my data" card: ask for a copy, watch it get built, and download
/// it. It owns its banners, so a screen or a sheet can host it. A host with its
/// own presentation context mounts `paeoniaTopBanner` itself.
struct DataExportSection: View {
    @Bindable var viewModel: DataExportViewModel
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            switch viewModel.phase {
            case .loading:
                header(.privacySafetyDataExportTitle, message: .privacySafetyDataExportDescription)
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text(.privacySafetyLoading))
            case .notRequested:
                askContent(message: .privacySafetyDataExportDescription, button: .privacySafetyDataExportPrepare)
            case .sending:
                askContent(
                    message: .privacySafetyDataExportDescription,
                    button: .privacySafetyDataExportPrepare,
                    isSending: true
                )
            case let .preparing(progress):
                preparingContent(progress: progress)
            case let .ready(export):
                readyContent(export)
            case let .downloading(_, progress):
                downloadingContent(progress)
            case .failed:
                failedContent
            case .expired:
                askContent(
                    title: .privacySafetyDataExportExpiredTitle,
                    message: .privacySafetyDataExportExpiredMessage,
                    button: .privacySafetyDataExportPrepareAgain
                )
            }
        }
        .padding(PaeoniaSpacing.space16)
        .task {
            await viewModel.load()
        }
        .task {
            await viewModel.observe()
        }
        .task(id: viewModel.phase) {
            if case .ready = viewModel.phase {
                await DeliveredNotifications.clear(types: ["data_export_ready"])
            }
        }
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else {
                return
            }
            showBanner(for: notice)
            viewModel.dismissNotice()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.filesToShare != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.finishedSharing()
                    }
                }
            )
        ) {
            DataExportShareSheet(files: viewModel.filesToShare ?? []) {
                viewModel.finishedSharing()
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(.paeoniaBackgroundPrimary)
        }
    }

    // MARK: - States

    private func askContent(
        title: LocalizedStringResource = .privacySafetyDataExportTitle,
        message: LocalizedStringResource,
        button: LocalizedStringResource,
        isSending: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            header(title, message: message)

            Toggle(isOn: $viewModel.includesFiles) {
                Text(.privacySafetyDataExportIncludeFilesTitle)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(.privacySafetyDataExportIncludeFilesDescription)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .disabled(isSending)

            Button {
                Task { await viewModel.prepare() }
            } label: {
                Text(button)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: isSending))
            .disabled(isSending)
        }
    }

    private func preparingContent(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            header(.privacySafetyDataExportPreparingTitle, message: .privacySafetyDataExportPreparingMessage)
            progressBar(progress, label: .privacySafetyDataExportPreparingTitle)
        }
    }

    private func readyContent(_ export: DataExport) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            readyDetails(export)

            Button {
                Task { await viewModel.download() }
            } label: {
                Text(.privacySafetyDataExportDownload)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())

            Button {
                Task { await viewModel.deleteCopy() }
            } label: {
                Text(.privacySafetyDataExportDelete)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
        }
    }

    private func readyDetails(_ export: DataExport) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Label {
                Text(.privacySafetyDataExportReadyTitle)
            } icon: {
                Image(systemName: "checkmark.circle")
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.bodyEmphasis)
            .foregroundStyle(.paeoniaSuccess)

            if let expiresAt = export.expiresAt {
                let date = expiresAt.formatted(date: .abbreviated, time: .shortened)
                detail(.privacySafetyDataExportReadyExpires(date))
            }
            detail(.privacySafetyDataExportReadySize(export.byteSize.formatted(.byteCount(style: .file))))
            if export.partCount > 1 {
                detail(.privacySafetyDataExportReadyParts(Int32(export.partCount)))
            }
            if export.skippedFileCount > 0 {
                detail(.privacySafetyDataExportReadySkipped(Int32(export.skippedFileCount)))
            }
        }
    }

    private func downloadingContent(_ progress: DataExportDownloadProgress) -> some View {
        let title: LocalizedStringResource = progress.partCount > 1
            ? .privacySafetyDataExportDownloadingPart(Int32(progress.part), Int32(progress.partCount))
            : .privacySafetyDataExportDownloading
        return VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(title)
            .font(PaeoniaTypography.bodyEmphasis)
            .foregroundStyle(.paeoniaTextPrimary)

            progressBar(progress.fraction, label: .privacySafetyDataExportDownloading)
        }
    }

    private var failedContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            header(.privacySafetyDataExportFailedTitle, message: .privacySafetyDataExportFailedMessage)

            Button {
                Task { await viewModel.prepare() }
            } label: {
                Text(.commonTryAgain)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())

            PaeoniaSupportLink()
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Pieces

    private func header(_ title: LocalizedStringResource, message: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(title)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)

            detail(message)
        }
    }

    private func detail(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func progressBar(_ fraction: Double, label: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(.paeoniaAccentPrimary)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))

            Text(fraction, format: .percent.precision(.fractionLength(0)))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .monospacedDigit()
                .accessibilityHidden(true)
        }
    }

    // MARK: - Banners

    private func showBanner(for notice: DataExportViewModel.Notice) {
        switch notice {
        case .limitReached:
            bannerCenter.show(
                .info(
                    title: String(localized: .privacySafetyDataExportLimitTitle),
                    message: String(localized: .privacySafetyDataExportLimitMessage)
                )
            )
        case .notAvailable:
            bannerCenter.show(
                .info(
                    title: String(localized: .privacySafetyDataExportExpiredTitle),
                    message: String(localized: .privacySafetyDataExportExpiredMessage)
                )
            )
        case let .loadFailed(failure):
            showError(.privacySafetyDataExportLoadFailedTitle, failure: failure)
        case let .requestFailed(failure):
            showError(.privacySafetyDataExportRequestFailedTitle, failure: failure)
        case let .downloadFailed(failure):
            showError(.privacySafetyDataExportDownloadFailedTitle, failure: failure)
        case let .deleteFailed(failure):
            showError(.privacySafetyDataExportDeleteFailedTitle, failure: failure)
        }
    }

    /// Only a phone without a connection is told to check it.
    private func showError(_ title: LocalizedStringResource, failure: PaeoniaFailure) {
        let message: LocalizedStringResource = switch failure {
        case .offline:
            .privacySafetyDataExportOfflineMessage
        case .other:
            .commonActionFailedMessage
        }
        bannerCenter.show(.error(title: String(localized: title), message: String(localized: message)))
    }
}

/// The iOS share sheet for the downloaded zip files, where the person picks
/// Save to Files, AirDrop or another app.
struct DataExportShareSheet: UIViewControllerRepresentable {
    let files: [URL]
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: files, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onFinish()
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
