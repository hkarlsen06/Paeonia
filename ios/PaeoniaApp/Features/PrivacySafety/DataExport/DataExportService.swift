import Foundation

/// "Download my data": asks the server for a copy, follows its progress, and
/// downloads the zip files of a ready copy.
nonisolated protocol DataExportServicing: Sendable {
    /// Emits the newest copy now and again whenever it changes on the server.
    /// Nil means the person never asked for one. The stream ends when the
    /// consuming task is cancelled.
    func exportUpdates() -> AsyncStream<DataExport?>

    func loadExport() async throws -> DataExport?

    /// Starts a copy, or returns the one that is already being built. Throws
    /// `DataExportServiceError.limitReached` after three copies in a day.
    func requestExport(includeFiles: Bool) async throws -> DataExport

    /// Downloads every zip file of a ready copy to a folder on this phone and
    /// returns their locations, in order.
    func downloadFiles(
        of export: DataExport,
        onProgress: @escaping @Sendable (DataExportDownloadProgress) -> Void
    ) async throws -> [URL]

    /// Deletes the copy from the server before it expires.
    func deleteExport(_ export: DataExport) async throws

    /// Removes the downloaded files from this phone.
    func removeDownloadedFiles(of export: DataExport)
}

nonisolated extension DataExportServicing {
    /// Services without a live source emit nothing.
    func exportUpdates() -> AsyncStream<DataExport?> {
        AsyncStream { $0.finish() }
    }
}

nonisolated struct DataExportService: DataExportServicing {
    private let client: PaeoniaConvexClient
    private let downloader: any DataExportFileDownloading
    private let language: String

    init(
        client: PaeoniaConvexClient,
        downloader: any DataExportFileDownloading = URLSessionDataExportDownloader(),
        language: String = Locale.preferredLanguages.first ?? "en"
    ) {
        self.client = client
        self.downloader = downloader
        self.language = language
    }

    func exportUpdates() -> AsyncStream<DataExport?> {
        ScreenLiveUpdates.values(
            "dataExportStatus:get_data_export",
            as: RemoteDataExport?.self
        ) { row in
            row?.export
        }
    }

    func loadExport() async throws -> DataExport? {
        let row: RemoteDataExport? = try await client.query("dataExportStatus:get_data_export")
        return row?.export
    }

    func requestExport(includeFiles: Bool) async throws -> DataExport {
        do {
            let row: RemoteDataExport = try await client.mutation(
                "dataExport:request_data_export",
                args: RequestArguments(includeFiles: includeFiles, language: language)
            )
            return row.export
        } catch let error as PaeoniaConvexError {
            if case .server(code: "53300", message: _) = error {
                throw DataExportServiceError.limitReached
            }
            throw error
        }
    }

    func downloadFiles(
        of export: DataExport,
        onProgress: @escaping @Sendable (DataExportDownloadProgress) -> Void
    ) async throws -> [URL] {
        let links: [DataExportDownloadLink]
        do {
            links = try await client.mutation(
                "dataExport:create_data_export_download_links",
                args: ExportArguments(exportID: export.id)
            )
        } catch let error as PaeoniaConvexError {
            if case .server(code: PaeoniaConvexError.accessDeniedCode, message: _) = error {
                throw DataExportServiceError.notAvailable
            }
            throw error
        }
        let ordered = links.sorted { $0.partNumber < $1.partNumber }
        guard !ordered.isEmpty else {
            throw DataExportServiceError.notAvailable
        }

        let directory = Self.downloadDirectory(for: export)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let totalBytes = max(ordered.reduce(Int64(0)) { $0 + $1.byteSize }, 1)
        var finishedBytes: Int64 = 0
        var files = [URL]()
        for (index, link) in ordered.enumerated() {
            let base = finishedBytes
            let part = index + 1
            let count = ordered.count
            let start = Double(base) / Double(totalBytes)
            onProgress(DataExportDownloadProgress(part: part, partCount: count, fraction: start))
            let file = try await downloader.download(link, to: directory) { received in
                let fraction = min(Double(base + received) / Double(totalBytes), 1)
                onProgress(DataExportDownloadProgress(part: part, partCount: count, fraction: fraction))
            }
            files.append(file)
            finishedBytes += link.byteSize
        }
        return files
    }

    func deleteExport(_ export: DataExport) async throws {
        try await client.mutation(
            "dataExport:delete_data_export",
            args: ExportArguments(exportID: export.id)
        )
    }

    func removeDownloadedFiles(of export: DataExport) {
        try? FileManager.default.removeItem(at: Self.downloadDirectory(for: export))
    }

    private static func downloadDirectory(for export: DataExport) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "PaeoniaData-\(export.id.uuidString)")
    }
}

nonisolated private struct RequestArguments: Encodable {
    let includeFiles: Bool
    let language: String

    enum CodingKeys: String, CodingKey {
        case includeFiles = "p_include_files"
        case language = "p_language"
    }
}

nonisolated private struct ExportArguments: Encodable {
    let exportID: UUID

    enum CodingKeys: String, CodingKey {
        case exportID = "p_export_id"
    }
}

nonisolated enum DataExportServiceFactory {
    static func makeDefault() -> (any DataExportServicing)? {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return nil
        }

        return DataExportService(client: client)
    }
}
