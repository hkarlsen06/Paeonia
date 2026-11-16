import CoreTransferable
import Foundation
import os
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// How long a video may run where it is sent, and what to tell the person about a video
/// that could not be added.
nonisolated enum VideoLengthCap: Sendable {
    /// Chat and memories.
    case threeMinutes
    /// Stories.
    case oneMinute

    var maxDurationMs: Int {
        switch self {
        case .threeMinutes: 180_000
        case .oneMinute: 60_000
        }
    }

    /// Nil for a cancelled preparation, which the person caused or which a privacy purge ended.
    func message(for error: any Error) -> LocalizedStringResource? {
        switch error {
        case is CancellationError: nil
        case VideoTranscodeError.tooLong:
            self == .oneMinute ? .mediaVideoTooLongOneMinute : .mediaVideoTooLongThreeMinutes
        default: .mediaVideoPrepareFailed
        }
    }
}

extension PhotosPickerItem {
    var isVideo: Bool {
        supportedContentTypes.contains { $0.conforms(to: .movie) }
    }
}

/// A video from the photo picker. The picker deletes its file when the import returns, so
/// the importer copies it into the temporary folder first.
nonisolated struct PickedVideo: Transferable {
    let fileURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let directory = VideoPreparation.workingDirectoryURL()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let pathExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = directory.appendingPathComponent("\(UUID().uuidString.lowercased()).\(pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            // A copy keeps the original's date, and the launch sweep deletes working files
            // dated before the app started.
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: copy.path)
            return PickedVideo(fileURL: copy)
        }
    }
}

/// Makes a picked or recorded video ready to send, for chat, memories and stories.
///
/// The picked copy and the mp4 being written stay in the temporary folder. Only a finished
/// mp4 moves into the caller's folder in `PreparedVideo.outgoingMediaDirectoryURL()`, and only
/// while no privacy purge ran since the caller took its ticket. The purge deletes that
/// folder, and a preparation that finished later would otherwise put a file back.
nonisolated enum VideoPreparation {
    /// Taken when a pick starts, or when a recording is handed over to be prepared.
    struct Ticket: Equatable, Sendable {
        fileprivate let generation: Int
    }

    private static let generation = OSAllocatedUnfairLock(initialState: 0)

    static func ticket() -> Ticket {
        Ticket(generation: generation.withLock { $0 })
    }

    /// False once a privacy purge ran after `ticket` was taken. A pick then belongs to
    /// content the purge removed, so it must not be added.
    static func isCurrent(_ ticket: Ticket) -> Bool {
        generation.withLock { $0 == ticket.generation }
    }

    /// The privacy purge calls this before it deletes the outgoing and working folders.
    static func invalidateTickets() {
        generation.withLock { $0 += 1 }
    }

    static func workingDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PreparingVideos", isDirectory: true)
    }

    /// Creates `directory` inside the outgoing folder. Backups skip that folder, because its
    /// files wait there only until they are sent.
    static func createOutgoingDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var outgoing = PreparedVideo.outgoingMediaDirectoryURL()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try outgoing.setResourceValues(values)
    }

    /// Copies a library pick out of the picker and prepares it.
    static func prepare(
        _ item: PhotosPickerItem,
        into directory: URL,
        cap: VideoLengthCap,
        ticket: Ticket
    ) async throws -> PreparedVideo {
        let picked: PickedVideo?
        do {
            picked = try await item.loadTransferable(type: PickedVideo.self)
        } catch {
            throw error is CancellationError ? error : VideoTranscodeError.unreadable
        }
        guard let picked else { throw VideoTranscodeError.unreadable }
        return try await prepare(source: picked.fileURL, into: directory, cap: cap, ticket: ticket)
    }

    /// Writes the mp4 for `source` into `directory`, then deletes `source`. With
    /// `keepsSourceOnFailure`, a failed preparation keeps it, such as a camera recording
    /// the person may want to try again. After a privacy purge nothing is kept, and this
    /// throws `CancellationError`.
    @concurrent
    static func prepare(
        source: URL,
        into directory: URL,
        cap: VideoLengthCap,
        ticket: Ticket,
        keepsSourceOnFailure: Bool = false
    ) async throws -> PreparedVideo {
        var succeeded = false
        defer {
            if succeeded || !keepsSourceOnFailure || !isCurrent(ticket) {
                try? FileManager.default.removeItem(at: source)
            }
        }
        let video = try await transcode(source, cap: cap, ticket: ticket)
        // The server refuses a bigger file, and the upload would fail on every retry.
        guard video.byteSize <= MediaUpload.maxVideoByteSize else {
            try? FileManager.default.removeItem(at: video.fileURL)
            throw VideoTranscodeError.failed
        }
        let destination = directory.appendingPathComponent(video.fileURL.lastPathComponent, isDirectory: false)
        do {
            // Under the lock, so a purge either comes first and stops the move, or comes
            // after and deletes the moved file.
            try generation.withLock { current in
                guard current == ticket.generation else { throw CancellationError() }
                try createOutgoingDirectory(directory)
                try FileManager.default.moveItem(at: video.fileURL, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: video.fileURL)
            throw error
        }
        succeeded = true
        return PreparedVideo(
            fileURL: destination,
            width: video.width,
            height: video.height,
            durationMs: video.durationMs,
            byteSize: video.byteSize
        )
    }

    /// The phone stops the video encoder while the app is in the background, so a
    /// preparation the person leaves fails. Then this waits until the app is in front again
    /// and runs once more from the same source. A second failure is final.
    @MainActor
    private static func transcode(_ source: URL, cap: VideoLengthCap, ticket: Ticket) async throws -> PreparedVideo {
        let start = AppForeground.stint()
        do {
            return try await transcodeOnce(source, cap: cap, ticket: ticket)
        } catch let error as VideoTranscodeError
            where error != .tooLong && (start == nil || AppForeground.stint() != start) {}
        await untilActive()
        try Task.checkCancellation()
        return try await transcodeOnce(source, cap: cap, ticket: ticket)
    }

    @concurrent
    private static func transcodeOnce(
        _ source: URL, cap: VideoLengthCap, ticket: Ticket
    ) async throws -> PreparedVideo {
        do {
            return try await VideoTranscoder.transcode(
                source, into: workingDirectoryURL(), maxDurationMs: cap.maxDurationMs
            )
        } catch {
            guard isCurrent(ticket) else { throw CancellationError() }
            throw error
        }
    }

    /// Returns at once when the app is in front. A cancelled task stops waiting.
    @MainActor
    private static func untilActive() async {
        guard UIApplication.shared.applicationState != .active else { return }
        // Nothing suspends between the check and the first `next()`, and the notification
        // posts on the main actor, so it can't slip in between.
        for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
            return
        }
    }
}
