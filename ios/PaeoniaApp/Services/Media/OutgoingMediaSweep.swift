import Darwin
import Foundation

/// Deletes chat GIFs and videos and memory videos waiting to be sent that nothing names any
/// more, and videos left half prepared. A file can lose its last reference without being
/// deleted, such as when the app quits between preparing a video and saving the draft that
/// names it, or while a memory form held picks.
///
/// A file stays when a queued send or memory save, a chat message still sending or failed, or a
/// saved chat or memory draft names it, and when it changed after this app process started, because
/// something open now may name it. Runs once per launch, for the signed-in account. Signing
/// out clears the whole folder, so another account's sends and messages name nothing here.
enum OutgoingMediaSweep {
    static func run(
        ownerUserID: UUID,
        pendingOperationStore: any PendingSyncOperationPersisting =
            SwiftDataPendingSyncOperationRepository(container: PaeoniaLocalStore.shared.container),
        chatCache: any ThreadChatCaching = FileThreadChatCache.shared,
        chatDrafts: FileThreadChatAttachmentDraftStore = .shared,
        memoryDrafts: LocalMemoryDraftStore = .shared
    ) async {
        guard let processStart = processStartDate() else { return }
        var chatNames = chatDrafts.fileNamesInAllDrafts()
        for kind in [SyncPendingOperationKind.createChatThreadWithMessage, .sendThreadMessage] {
            // Without the queue, any file may be one it names.
            guard let operations = try? await pendingOperationStore.inFlightOperations(
                ownerUserID: ownerUserID,
                kind: kind
            ) else { return }
            chatNames.formUnion(operations.flatMap { attachmentFileNames(in: $0, of: kind) })
        }
        chatNames.formUnion(
            await chatCache.unsentMessages(ownerUserID: ownerUserID)
                .flatMap { $0.attachments ?? [] }
                .compactMap { $0.localFileURL?.lastPathComponent }
        )
        await deleteFiles(in: ThreadChatMediaFiles.directory, except: chatNames, changedBefore: processStart)
        var memoryNames = memoryDrafts.videoFileNamesInAllDrafts()
        for kind in [SyncPendingOperationKind.createMemory, .attachMemoryMedia] {
            guard let operations = try? await pendingOperationStore.inFlightOperations(
                ownerUserID: ownerUserID,
                kind: kind
            ) else { return }
            memoryNames.formUnion(
                operations.flatMap(MemoryQueuedUploads.uploads(in:)).compactMap { $0.videoFileURL?.lastPathComponent }
            )
        }
        await deleteFiles(in: MemoryDraftMedia.videoDirectoryURL(), except: memoryNames, changedBefore: processStart)
        // Preparing a video never outlives its process, so an older file here is from one that never finished.
        await deleteFiles(in: VideoPreparation.workingDirectoryURL(), except: [], changedBefore: processStart)
    }

    private static func attachmentFileNames(
        in operation: PendingSyncOperationSnapshot,
        of kind: SyncPendingOperationKind
    ) -> [String] {
        guard let data = operation.requestData else { return [] }
        let decoder = JSONDecoder()
        let attachments = kind == .sendThreadMessage
            ? (try? decoder.decode(SendChatMessagePayload.self, from: data))?.attachments
            : (try? decoder.decode(CreateChatThreadPayload.self, from: data))?.attachments
        return (attachments?.pendingAttachments ?? []).compactMap { $0.localFileURL?.lastPathComponent }
    }

    @concurrent
    private nonisolated static func deleteFiles(
        in directory: URL,
        except kept: Set<String>,
        changedBefore date: Date
    ) async {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files where !kept.contains(file.lastPathComponent) {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            guard let changed = values?.contentModificationDate, changed < date
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private nonisolated static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
