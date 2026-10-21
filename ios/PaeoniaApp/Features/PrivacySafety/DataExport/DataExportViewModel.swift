import Foundation
import Observation

/// Drives "Download my data": asking for a copy, watching it get built, and
/// downloading it. The server builds the copy, so the person can leave the
/// screen while it works.
@MainActor
@Observable
final class DataExportViewModel {
    enum Notice: Equatable {
        case loadFailed(PaeoniaFailure)
        case requestFailed(PaeoniaFailure)
        case limitReached
        case downloadFailed(PaeoniaFailure)
        case notAvailable
        case deleteFailed(PaeoniaFailure)
    }

    /// What the card shows. The server's copy decides it, plus the two things
    /// only this phone knows: a request being sent and a download running.
    enum Phase: Equatable {
        case loading
        case notRequested
        case sending
        case preparing(progress: Double)
        case ready(DataExport)
        case downloading(DataExport, DataExportDownloadProgress)
        case failed
        case expired
    }

    private let service: (any DataExportServicing)?

    private(set) var export: DataExport?
    private(set) var hasLoaded = false
    private(set) var isSending = false
    private(set) var downloadProgress: DataExportDownloadProgress?
    private(set) var notice: Notice?
    /// The downloaded zip files. The view hands them to the share sheet.
    var filesToShare: [URL]?
    /// Whether the next copy holds photos, voice messages and drawings. They make
    /// most of a copy's size, so the person can leave them out.
    var includesFiles = true

    init(service: (any DataExportServicing)? = DataExportServiceFactory.makeDefault()) {
        self.service = service
    }

    var phase: Phase {
        if let downloadProgress, let export {
            return .downloading(export, downloadProgress)
        }
        if isSending {
            return .sending
        }
        guard let export else {
            return hasLoaded ? .notRequested : .loading
        }
        switch export.status {
        case .preparing:
            return .preparing(progress: export.progress)
        case .ready:
            return .ready(export)
        case .failed:
            return .failed
        case .expired:
            return .expired
        }
    }

    func load() async {
        guard let service else {
            notice = .loadFailed(.other)
            hasLoaded = true
            return
        }
        do {
            export = try await service.loadExport()
            hasLoaded = true
        } catch {
            guard !Task.isCancelled, !error.isCancellation else {
                return
            }
            notice = .loadFailed(PaeoniaFailure(error))
            hasLoaded = true
        }
    }

    /// Applies the server's progress as it changes. Runs until the screen's task
    /// is cancelled.
    func observe() async {
        guard let service else {
            return
        }
        for await latest in service.exportUpdates() {
            export = latest
            hasLoaded = true
        }
    }

    func prepare() async {
        guard let service, !isSending, export?.status != .preparing else {
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            export = try await service.requestExport(includeFiles: includesFiles)
            hasLoaded = true
        } catch DataExportServiceError.limitReached {
            notice = .limitReached
        } catch {
            guard !Task.isCancelled, !error.isCancellation else {
                return
            }
            notice = .requestFailed(PaeoniaFailure(error))
        }
    }

    func download() async {
        guard let service, let export, export.status == .ready, downloadProgress == nil else {
            return
        }
        downloadProgress = DataExportDownloadProgress(part: 1, partCount: max(export.partCount, 1), fraction: 0)
        defer { downloadProgress = nil }
        do {
            let files = try await service.downloadFiles(of: export) { [weak self] progress in
                Task { @MainActor in
                    // A report that arrives after the download ended must not bring the bar back.
                    guard let self, self.downloadProgress != nil else {
                        return
                    }
                    self.downloadProgress = progress
                }
            }
            filesToShare = files
        } catch DataExportServiceError.notAvailable {
            notice = .notAvailable
            await load()
        } catch {
            guard !Task.isCancelled, !error.isCancellation else {
                return
            }
            notice = .downloadFailed(PaeoniaFailure(error))
        }
    }

    /// The share sheet closed, so the downloaded files are no longer needed here.
    func finishedSharing() {
        filesToShare = nil
        if let service, let export {
            service.removeDownloadedFiles(of: export)
        }
    }

    func deleteCopy() async {
        guard let service, let export else {
            return
        }
        do {
            try await service.deleteExport(export)
            await load()
        } catch {
            guard !Task.isCancelled, !error.isCancellation else {
                return
            }
            notice = .deleteFailed(PaeoniaFailure(error))
        }
    }

    func dismissNotice() {
        notice = nil
    }
}
