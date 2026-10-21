import Foundation

/// Where a "Download my data" copy is. A copy is built on the server, so it
/// spends a while `preparing` before the person can download it.
nonisolated enum DataExportStatus: String, Decodable, Equatable, Sendable {
    case preparing
    case ready
    case failed
    case expired
}

/// The person's newest copy of their data, as the server reports it.
nonisolated struct DataExport: Equatable, Identifiable, Sendable {
    let id: UUID
    let status: DataExportStatus
    /// 0 to 1 while the copy is being built.
    let progress: Double
    let includesFiles: Bool
    let readyAt: Date?
    /// When the server deletes the files of a ready copy.
    let expiresAt: Date?
    /// How many zip files the copy has. A lot of photos make several.
    let partCount: Int
    let byteSize: Int64
    /// Photos, voice messages and drawings that could not be included.
    let skippedFileCount: Int
}

nonisolated struct RemoteDataExport: Decodable, Equatable, Sendable {
    let id: UUID
    let status: DataExportStatus
    let progress: Double
    let includeFiles: Bool
    let readyAt: Date?
    let expiresAt: Date?
    let partCount: Int
    let byteSize: Int64
    let skippedFileCount: Int

    var export: DataExport {
        DataExport(
            id: id,
            status: status,
            progress: progress,
            includesFiles: includeFiles,
            readyAt: readyAt,
            expiresAt: expiresAt,
            partCount: partCount,
            byteSize: byteSize,
            skippedFileCount: skippedFileCount
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case progress
        case includeFiles = "include_files"
        case readyAt = "ready_at"
        case expiresAt = "expires_at"
        case partCount = "part_count"
        case byteSize = "byte_size"
        case skippedFileCount = "skipped_file_count"
    }
}

/// One signed link to one zip file of a ready copy. It works for an hour.
nonisolated struct DataExportDownloadLink: Decodable, Equatable, Sendable {
    let partNumber: Int
    let fileName: String
    let byteSize: Int64
    let url: URL

    enum CodingKeys: String, CodingKey {
        case partNumber = "part_number"
        case fileName = "file_name"
        case byteSize = "byte_size"
        case url
    }
}

/// How far a download of all the zip files has come.
nonisolated struct DataExportDownloadProgress: Equatable, Sendable {
    /// The zip file being downloaded, counted from 1.
    let part: Int
    let partCount: Int
    /// 0 to 1 across all zip files.
    let fraction: Double
}

nonisolated enum DataExportServiceError: Error, Equatable {
    /// The server refused the request: three copies a day is the limit.
    case limitReached
    /// The copy is gone, or it is not this person's.
    case notAvailable
    /// A downloaded file was empty or could not be saved.
    case downloadFailed
}
