import AVFoundation

nonisolated enum VideoFileCacheError: Error, Equatable, Sendable {
    /// The server has no file for this video, or will not give it to this phone.
    case unavailable
    /// The download was a web page, such as a captive portal's sign-in page.
    case notAVideo
}

/// Downloads videos to files in Caches and hands out their local URLs. A video goes
/// straight to disk through a download task, never into memory. The privacy purge
/// clears it, and deleting a video's message or memory evicts its file.
actor VideoFileCache: MediaCacheEvicting {
    /// A video someone opened to watch downloads at once. Posters wait for a turn.
    enum Priority {
        case poster
        case playback
    }

    nonisolated static let shared: VideoFileCache? = try? live()

    private let client: PaeoniaConvexClient
    private let directoryURL: URL
    private let expiresInSeconds = 3_600
    private var inFlightDownloads: [UUID: Download] = [:]
    /// Bumped by every purge, so a download that started before it drops its file
    /// instead of saving it.
    private(set) var privacyGeneration: UInt64 = 0
    /// A list of posters asks for every visible video at once. Two download at a time,
    /// and the rest wait their turn, so a slow connection still finishes one poster. A
    /// video opened to watch starts at once, outside these two.
    private static let maxConcurrentPosterDownloads = 2
    private var runningPosterDownloads = 0
    /// The turn resumes with true when it counts against the two.
    private var waitingDownloads: [(mediaAssetID: UUID, turn: CheckedContinuation<Bool, Never>)] = []

    init(client: PaeoniaConvexClient, directoryURL: URL = VideoFileCache.defaultDirectoryURL()) {
        self.client = client
        self.directoryURL = directoryURL
    }

    nonisolated static func live() throws -> VideoFileCache {
        VideoFileCache(client: try PaeoniaConvexClientProvider.shared.client())
    }

    /// A download and the number of callers waiting for it.
    private struct Download {
        let task: Task<URL, any Error>
        var priority: Priority
        var waiters = 1
    }

    /// The local file of a video that can play, downloading it the first time. A damaged
    /// file would fail the same way on every try, so it leaves the cache and throws
    /// `notAVideo`, and the next call downloads it anew. A `URLError` passes through, so
    /// `PaeoniaFailure` can tell an offline phone apart.
    func fileURL(for mediaAssetID: UUID, priority: Priority = .poster) async throws -> URL {
        let file = try await downloadedFile(for: mediaAssetID, priority: priority)
        try Task.checkCancellation()
        guard try await Self.isPlayable(file) else {
            // Another caller may have dropped this file already and started a new download.
            if inFlightDownloads[mediaAssetID] == nil {
                try? FileManager.default.removeItem(at: file)
            }
            throw VideoFileCacheError.notAVideo
        }
        return file
    }

    /// Callers asking for the same video share one download. It stops once every caller
    /// waiting for it has been cancelled, such as posters scrolled out of a list.
    private func downloadedFile(for mediaAssetID: UUID, priority: Priority) async throws -> URL {
        let cached = fileURL(forCached: mediaAssetID)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        let task: Task<URL, any Error>
        if var download = inFlightDownloads[mediaAssetID] {
            download.waiters += 1
            if priority == .playback {
                download.priority = .playback
                startWaitingDownload(of: mediaAssetID)
            }
            inFlightDownloads[mediaAssetID] = download
            task = download.task
        } else {
            let requested = privacyGeneration
            task = Task { try await self.download(mediaAssetID, privacyGeneration: requested) }
            inFlightDownloads[mediaAssetID] = Download(task: task, priority: priority)
        }
        defer {
            // A purge or the last waiter may have dropped it, and a newer download started since.
            if inFlightDownloads[mediaAssetID]?.task == task {
                inFlightDownloads[mediaAssetID] = nil
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.stopWaiting(for: task, of: mediaAssetID) }
        }
    }

    private func stopWaiting(for task: Task<URL, any Error>, of mediaAssetID: UUID) {
        guard var download = inFlightDownloads[mediaAssetID], download.task == task else { return }
        download.waiters -= 1
        if download.waiters > 0 {
            inFlightDownloads[mediaAssetID] = download
        } else {
            stop(mediaAssetID)
        }
    }

    /// Cancels the download and frees its place in line, so the line holds only downloads
    /// someone still waits for.
    private func stop(_ mediaAssetID: UUID) {
        inFlightDownloads.removeValue(forKey: mediaAssetID)?.task.cancel()
        startWaitingDownload(of: mediaAssetID)
    }

    /// False for a file that can't be read as a video. Only cancellation throws.
    private static func isPlayable(_ file: URL) async throws -> Bool {
        do {
            return try await AVURLAsset(url: file).load(.isPlayable)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            return false
        }
    }

    /// Seeds the cache with the file this phone just sent, so the sender never
    /// downloads their own video. Copies, because the outbox may still need `file`.
    /// `privacyGeneration` is the one read before the upload, so a purge since drops the copy.
    func store(_ file: URL, for mediaAssetID: UUID, privacyGeneration requested: UInt64) {
        guard requested == privacyGeneration else { return }
        let destination = fileURL(forCached: mediaAssetID)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        // On APFS this is a clone, so the copy costs no extra space until one side changes.
        try? FileManager.default.copyItem(at: file, to: destination)
    }

    func evict(mediaAssetIDs: [UUID]) {
        for mediaAssetID in mediaAssetIDs {
            stop(mediaAssetID)
            try? FileManager.default.removeItem(at: fileURL(forCached: mediaAssetID))
        }
    }

    func clearAll() async {
        privacyGeneration &+= 1
        let downloads = inFlightDownloads.values.map(\.task)
        for mediaAssetID in inFlightDownloads.keys {
            stop(mediaAssetID)
        }
        // A download that is saving its file right now finishes first and sees the new
        // generation, so nothing it wrote survives the delete below.
        for download in downloads {
            _ = try? await download.value
        }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func download(_ mediaAssetID: UUID, privacyGeneration requested: UInt64) async throws -> URL {
        let holdsPosterTurn = await takeDownloadTurn(for: mediaAssetID)
        defer { if holdsPosterTurn { endDownloadTurn() } }
        try Task.checkCancellation()
        guard let url = try await client.signedMediaURL(for: mediaAssetID, expiresInSeconds: expiresInSeconds) else {
            throw VideoFileCacheError.unavailable
        }
        let (downloadedURL, response) = try await URLSession.paeonia.download(from: url)
        defer { try? FileManager.default.removeItem(at: downloadedURL) }
        guard !Task.isCancelled, requested == privacyGeneration else { throw CancellationError() }

        if let statusCode = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(statusCode) {
            throw VideoFileCacheError.unavailable
        }
        let head = try? FileHandle(forReadingFrom: downloadedURL).read(upToCount: 64)
        guard !MediaDownloadCheck.isWebPage(head ?? Data(), mimeType: response.mimeType) else {
            throw VideoFileCacheError.notAVideo
        }

        let destination = fileURL(forCached: mediaAssetID)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: downloadedURL, to: destination)
        return destination
    }

    /// True when the download took one of the two poster turns. A stopped download is
    /// cancelled and never joins the line, so the line has no entries nobody will use.
    private func takeDownloadTurn(for mediaAssetID: UUID) async -> Bool {
        guard !Task.isCancelled, inFlightDownloads[mediaAssetID]?.priority == .poster else { return false }
        guard runningPosterDownloads >= Self.maxConcurrentPosterDownloads else {
            runningPosterDownloads += 1
            return true
        }
        // The download that ends hands its turn straight to the first one waiting.
        return await withCheckedContinuation { turn in
            waitingDownloads.append((mediaAssetID, turn))
        }
    }

    /// Starts a waiting download now, outside the two poster turns, because someone opened
    /// its video to watch or it stopped.
    private func startWaitingDownload(of mediaAssetID: UUID) {
        guard let index = waitingDownloads.firstIndex(where: { $0.mediaAssetID == mediaAssetID }) else { return }
        waitingDownloads.remove(at: index).turn.resume(returning: false)
    }

    private func endDownloadTurn() {
        if waitingDownloads.isEmpty {
            runningPosterDownloads -= 1
        } else {
            waitingDownloads.removeFirst().turn.resume(returning: true)
        }
    }

    private func fileURL(forCached mediaAssetID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(mediaAssetID.uuidString.lowercased()).mp4", isDirectory: false)
    }

    /// In Caches, so the private videos are not backed up and the system can reclaim
    /// the space. Anything removed downloads again the next time it plays.
    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Videos", isDirectory: true)
    }
}
