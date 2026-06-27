import Foundation

/// Stores the bytes of a picked-but-not-yet-sent answer photo (or voice note) in a
/// private app directory, keyed by the question instance. Keeping the bytes on disk
/// means a half-finished media answer survives closing the flow or relaunching the
/// app, and gives the upload the file to send. One staged file per instance, so
/// replacing the picked media overwrites cleanly.
nonisolated protocol DailyAnswerMediaDraftStoring: Sendable {
    func writeStagedMedia(_ data: Data, instanceID: UUID) throws
    func stagedMediaData(instanceID: UUID) -> Data?
    func removeStagedMedia(instanceID: UUID)
    func clearAll()
}

final class FileDailyAnswerMediaDraftStore: @unchecked Sendable, DailyAnswerMediaDraftStoring {
    private let directoryURL: URL

    nonisolated init(directoryURL: URL = FileDailyAnswerMediaDraftStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func live() -> FileDailyAnswerMediaDraftStore {
        FileDailyAnswerMediaDraftStore()
    }

    func writeStagedMedia(_ data: Data, instanceID: UUID) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: instanceID), options: [.atomic])
    }

    func stagedMediaData(instanceID: UUID) -> Data? {
        try? Data(contentsOf: fileURL(for: instanceID))
    }

    func removeStagedMedia(instanceID: UUID) {
        let url = fileURL(for: instanceID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    func clearAll() {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func fileURL(for instanceID: UUID) -> URL {
        directoryURL.appendingPathComponent(instanceID.uuidString.lowercased(), isDirectory: false)
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DailyAnswerMediaDrafts", isDirectory: true)
    }
}
