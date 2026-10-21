import Foundation

/// Saves one zip file of a copy on this phone.
nonisolated protocol DataExportFileDownloading: Sendable {
    /// Downloads `link` into `directory` and returns the saved file. `onBytes`
    /// reports how many bytes of this file have arrived.
    func download(
        _ link: DataExportDownloadLink,
        to directory: URL,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL
}

nonisolated struct URLSessionDataExportDownloader: DataExportFileDownloading {
    func download(
        _ link: DataExportDownloadLink,
        to directory: URL,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(
            from: link.url,
            delegate: BytesDelegate(onBytes: onBytes)
        )
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw DataExportServiceError.downloadFailed
        }
        // The server names the file. Only its last component is used, so a name
        // cannot point outside the folder.
        let name = (link.fileName as NSString).lastPathComponent
        guard !name.isEmpty else {
            throw DataExportServiceError.downloadFailed
        }
        let destination = directory.appending(path: name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}

nonisolated private final class BytesDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    private let onBytes: @Sendable (Int64) -> Void

    init(onBytes: @escaping @Sendable (Int64) -> Void) {
        self.onBytes = onBytes
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onBytes(totalBytesWritten)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The async download call moves the file itself.
    }
}
