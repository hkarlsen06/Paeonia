import Observation
import PhotosUI
import SwiftUI

/// The photos, GIFs and videos picked for the next chat message, ported from Tidex's
/// composer. Up to four per message. Each is prepared when it's picked, off the main
/// actor, so sending never waits on it: a photo is compressed with the same compressor
/// as memory photos, a GIF is kept as it is, and a video is made into a small mp4.
@Observable
final class ThreadChatAttachmentStaging {
    static let maximumAttachments = 4

    struct Staged: Identifiable, Equatable {
        let id: UUID
        /// The library pick it came from. Nil for a camera shot or a paste.
        let pickerItemID: String?
        var attachment: ThreadChatAttachment
    }

    private(set) var staged: [Staged] = [] {
        didSet { persistDraft() }
    }
    private var caption = ""
    /// Staging owns this callback so a pick finishing after the view disappears is still saved.
    @ObservationIgnored var onDraftChange: ((ThreadChatAttachmentDraft) -> Void)?
    /// Picks still loading or being prepared. While any are, the send button waits, so a
    /// half-loaded pick can't send.
    private var processingCount = 0
    private(set) var preparingVideoCount = 0
    /// Picks that are loading now. The picker sets its selection more than once, and a
    /// video takes seconds to prepare, so without this one pick would be staged twice.
    private var loadingPickerIDs: Set<String> = []
    /// Why the last pick could not be added. It shows above the field until the next pick.
    private(set) var notice: LocalizedStringResource?
    var pickerItems: [PhotosPickerItem] = [] {
        didSet { syncPicker() }
    }
    var isDrawerOpen = false
    var isShowingLibrary = false
    var isShowingCamera = false

    var isProcessing: Bool { processingCount > 0 }

    var attachments: [ThreadChatAttachment] {
        staged.map(\.attachment)
    }

    /// The library may hold this many, after camera shots and pastes already staged.
    var librarySelectionLimit: Int {
        max(1, Self.maximumAttachments - staged.count(where: { $0.pickerItemID == nil }))
    }

    var canAddAttachments: Bool {
        staged.count < Self.maximumAttachments
    }

    /// The camera takes photos only, and they stay JPEGs.
    func addCameraPhoto(_ data: Data) {
        guard canAddAttachments else { return }
        let ticket = VideoPreparation.ticket()
        process {
            if let attachment = await Self.compressCameraPhoto(data) {
                self.append(attachment, pickerItemID: nil, ticket: ticket)
            }
        }
    }

    /// A photo or a GIF pasted into the message field.
    func addPasted(_ data: Data) {
        guard canAddAttachments else { return }
        notice = nil
        let ticket = VideoPreparation.ticket()
        process {
            do {
                let attachment = try await Self.compressKeepingAnimation(data)
                self.append(attachment, pickerItemID: nil, ticket: ticket)
            } catch {
                self.notice = Self.notice(for: error)
            }
        }
    }

    /// Takes a pick out of the message, and deletes a GIF's or a prepared video's file.
    func remove(_ id: UUID) {
        guard let removed = staged.first(where: { $0.id == id }) else { return }
        unstage(removed)
        ThreadChatMediaFiles.delete([removed.attachment])
    }

    func setDescription(_ text: String, for id: UUID) {
        guard let index = staged.firstIndex(where: { $0.id == id }) else { return }
        staged[index].attachment.accessibilityText = text
    }

    func updateCaption(_ caption: String) {
        self.caption = caption
        persistDraft()
    }

    func restore(_ draft: ThreadChatAttachmentDraft) {
        caption = draft.caption
        // Prepared local copies are independent of a later photo-library selection.
        staged = draft.attachments.map { Staged(id: UUID(), pickerItemID: nil, attachment: $0) }
    }

    /// Clears what was sent. A sent GIF's or video's file now belongs to the send queue, so it stays.
    func removeSent(_ sent: [Staged]) {
        for item in sent where staged.contains(item) {
            unstage(item)
        }
        notice = nil
        if staged.isEmpty { isDrawerOpen = false }
    }

    /// Stages a prepared pick. Other picks may have filled the message while it was
    /// prepared, or a privacy purge may have run, and then it is dropped with its file.
    @discardableResult
    private func append(
        _ attachment: ThreadChatAttachment, pickerItemID: String?, ticket: VideoPreparation.Ticket
    ) -> Bool {
        guard canAddAttachments, VideoPreparation.isCurrent(ticket) else {
            ThreadChatMediaFiles.delete([attachment])
            return false
        }
        staged.append(Staged(id: UUID(), pickerItemID: pickerItemID, attachment: attachment))
        return true
    }

    private func unstage(_ item: Staged) {
        staged.removeAll { $0.id == item.id }
        // Clears the pick's check mark in the picker too.
        if let pickerItemID = item.pickerItemID {
            pickerItems.removeAll { $0.itemIdentifier == pickerItemID }
        }
    }

    private func persistDraft() {
        onDraftChange?(ThreadChatAttachmentDraft(attachments: attachments, caption: caption))
    }

    private func process(_ work: @escaping () async -> Void) {
        processingCount += 1
        Task {
            await work()
            processingCount -= 1
        }
    }

    /// Mirrors the picker's selection: new picks are loaded and staged, picks taken
    /// away are unstaged.
    private func syncPicker() {
        let selectedIDs = Set(pickerItems.compactMap(\.itemIdentifier))
        let deselected = staged.filter { item in
            item.pickerItemID.map { !selectedIDs.contains($0) } ?? false
        }
        staged.removeAll { deselected.contains($0) }
        ThreadChatMediaFiles.delete(deselected.map(\.attachment))
        let stagedIDs = Set(staged.compactMap(\.pickerItemID)).union(loadingPickerIDs)
        let added = pickerItems.filter { item in
            guard let id = item.itemIdentifier else { return false }
            return !stagedIDs.contains(id)
        }
        guard !added.isEmpty else { return }
        loadingPickerIDs.formUnion(added.compactMap(\.itemIdentifier))
        notice = nil
        let ticket = VideoPreparation.ticket()
        process {
            for item in added {
                guard let id = item.itemIdentifier else { continue }
                defer { self.loadingPickerIDs.remove(id) }
                guard self.canAddAttachments, let attachment = await self.load(item, ticket: ticket) else {
                    // A pick that could not be added loses its check mark, so it can be picked again.
                    self.pickerItems.removeAll { $0.itemIdentifier == id }
                    continue
                }
                // The pick may have been taken away while it loaded.
                guard self.pickerItems.contains(where: { $0.itemIdentifier == id }) else {
                    ThreadChatMediaFiles.delete([attachment])
                    continue
                }
                if !self.append(attachment, pickerItemID: id, ticket: ticket) {
                    self.pickerItems.removeAll { $0.itemIdentifier == id }
                }
            }
        }
    }

    private func load(_ item: PhotosPickerItem, ticket: VideoPreparation.Ticket) async -> ThreadChatAttachment? {
        guard item.isVideo else {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ImageCompressor.CompressionError.unreadable
                }
                return try await Self.compressKeepingAnimation(data)
            } catch {
                notice = Self.notice(for: error)
                return nil
            }
        }
        preparingVideoCount += 1
        defer { preparingVideoCount -= 1 }
        do {
            let video = try await VideoPreparation.prepare(
                item, into: ThreadChatMediaFiles.directory, cap: .threeMinutes, ticket: ticket
            )
            return ThreadChatAttachment(
                kind: .video,
                local: .file(name: video.fileURL.lastPathComponent),
                width: video.width,
                height: video.height,
                durationMs: video.durationMs
            )
        } catch {
            notice = VideoLengthCap.threeMinutes.message(for: error)
            return nil
        }
    }

    private static func notice(for error: any Error) -> LocalizedStringResource? {
        switch error {
        case is CancellationError: nil
        case ImageCompressor.CompressionError.animatedGIFTooBig: .mediaGifTooBig
        default: .dailyChatComposerPickFailed
        }
    }

    @concurrent
    private nonisolated static func compressKeepingAnimation(_ data: Data) async throws -> ThreadChatAttachment {
        let compressed = try ImageCompressor.compressKeepingAnimation(data)
        let isGIF = compressed.mediaType == "image/gif"
        return ThreadChatAttachment(
            kind: isGIF ? .gif : .photo,
            local: isGIF ? .file(name: try ThreadChatMediaFiles.storeGIF(compressed.data)) : .bytes(compressed.data),
            width: compressed.width,
            height: compressed.height
        )
    }

    @concurrent
    private nonisolated static func compressCameraPhoto(_ data: Data) async -> ThreadChatAttachment? {
        ImageCompressor.compress(data).map {
            ThreadChatAttachment(kind: .photo, local: .bytes($0.data), width: $0.width, height: $0.height)
        }
    }
}

/// The drawer under the field: a strip of recent attachments to tap, and buttons for the
/// whole library and the camera. Like Tidex's attachment drawer.
struct ThreadChatAttachmentDrawer: View {
    @Bindable var staging: ThreadChatAttachmentStaging

    private static let pickerHeight: CGFloat = 168

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            PhotosPicker(
                selection: $staging.pickerItems,
                maxSelectionCount: staging.librarySelectionLimit,
                selectionBehavior: .continuous,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            ) {
                Text(.dailyChatComposerLibrary)
            }
            .photosPickerStyle(.compact)
            .photosPickerDisabledCapabilities(.selectionActions)
            .photosPickerAccessoryVisibility(.hidden)
            .frame(height: Self.pickerHeight)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))

            HStack(spacing: PaeoniaSpacing.space8) {
                tile(systemImage: "photo.on.rectangle", title: .dailyChatComposerLibrary) {
                    staging.isShowingLibrary = true
                }
                tile(systemImage: "camera", title: .dailyChatComposerCamera) {
                    staging.isShowingCamera = true
                }
                .disabled(!staging.canAddAttachments)
            }
        }
        .padding(PaeoniaSpacing.space8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous))
    }

    private func tile(
        systemImage: String,
        title: LocalizedStringResource,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                Color.paeoniaTextPrimary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The picked attachments above the field, each with a button to take it away.
struct ThreadChatStagedAttachmentsRow: View {
    let staging: ThreadChatAttachmentStaging

    @AccessibilityPresentation(.media) private var showsMedia

    var body: some View {
        if showsMedia || staging.staged.contains(where: {
            DailyAnswerDraft.measuredLength(of: $0.attachment.accessibilityText ?? "") > 10_000
        }) {
            describedAttachments
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: PaeoniaSpacing.space8) {
                    ForEach(staging.staged) { thumbnail($0, side: 64) }
                    processingIndicator
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var describedAttachments: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            ForEach(staging.staged) { item in
                let isVideo = item.attachment.kind == .video
                HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
                    thumbnail(item, side: 64)
                    VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                        Text(isVideo ? .dailyChatComposerVideoDescription : .mediaAccessibilityPhotoDescription)
                            .font(PaeoniaTypography.caption)
                        PaeoniaMultilineTextField(
                            text: Binding(
                                get: { staging.staged.first { $0.id == item.id }?.attachment.accessibilityText ?? "" },
                                set: { staging.setDescription($0, for: item.id) }
                            ),
                            label: isVideo ? .dailyChatComposerVideoDescription : .mediaAccessibilityPhotoDescription,
                            prompt: Text(isVideo ? .dailyChatComposerVideoHint : .mediaAccessibilityPhotoHint)
                        )
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        if DailyAnswerDraft.measuredLength(of: item.attachment.accessibilityText ?? "") > 10_000 {
                            Text(.mediaAccessibilityTooLong).foregroundStyle(.paeoniaErrorText)
                        }
                    }
                }
            }
            processingIndicator
        }
    }

    /// A video can take a while to prepare, so it says what it is waiting for.
    @ViewBuilder
    private var processingIndicator: some View {
        if staging.preparingVideoCount > 0 {
            HStack(spacing: PaeoniaSpacing.space8) {
                ProgressView()
                Text(.dailyChatComposerPreparingVideo)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .accessibilityElement(children: .combine)
        } else if staging.isProcessing {
            ProgressView()
        }
    }

    private func thumbnail(_ item: ThreadChatAttachmentStaging.Staged, side: CGFloat) -> some View {
        ThreadChatAttachmentCard(
            attachment: item.attachment,
            size: CGSize(width: side, height: side),
            shape: UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: PaeoniaRadius.radius16, bottomLeading: PaeoniaRadius.radius16,
                bottomTrailing: PaeoniaRadius.radius16, topTrailing: PaeoniaRadius.radius16
            ), style: .continuous),
            showsVideoLength: false
        )
        .overlay(alignment: .topTrailing) {
            Button {
                staging.remove(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.black.opacity(0.46), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
                    // The circle stays small. The tap area is 44pt.
                    .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel(Text(Self.removeLabel(for: item.attachment.kind)))
        }
    }

    private static func removeLabel(for kind: ThreadChatAttachment.Kind) -> LocalizedStringResource {
        switch kind {
        case .photo: .dailyChatComposerRemovePhoto
        case .gif: .dailyChatComposerRemoveGif
        case .video: .dailyChatComposerRemoveVideo
        }
    }
}
