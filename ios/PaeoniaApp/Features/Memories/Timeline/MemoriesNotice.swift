import Foundation

/// An outcome of a memory action, shown through the shared banner. Copy says what
/// happened in plain words; the underlying error is logged in debug builds only.
enum MemoriesNotice: Equatable {
    case createFailed
    case editFailed
    case loadFailed
    case draftSaveFailed
    case photoUploadFailed
    case deleteFailed
    case noteFailed
    /// The partner deleted the memory while this person was changing it.
    case memoryRemoved
    /// The title or note is longer than the server accepts.
    case textTooLong
    /// The person deleted their memory after it joined the partner's memory for the visit, so
    /// only their photos and note came off.
    case ownPartRemovedAfterJoin
    /// A place picked for a memory that joined the partner's memory meanwhile. The partner's
    /// memory keeps its own place.
    case placeNotAddedAfterJoin
    case photoSaved
    case photoSaveDenied
    case photoSaveFailed

    var banner: PaeoniaBannerContent {
        switch self {
        case .photoSaved:
            .info(message: String(localized: .memoriesNoticePhotoSavedMessage), systemImage: "square.and.arrow.down")
        case .ownPartRemovedAfterJoin, .placeNotAddedAfterJoin:
            .info(message: String(localized: message), systemImage: "info.circle")
        default:
            .error(title: String(localized: title), message: String(localized: message), timing: timing)
        }
    }

    /// Photo access is fixed in Settings, and a removed memory means the changes are gone.
    private var timing: PaeoniaBannerTiming {
        self == .photoSaveDenied || self == .memoryRemoved ? .untilDismissed : .standard
    }

    private var title: LocalizedStringResource {
        switch self {
        case .createFailed:
            .memoriesNoticeCreateFailedTitle
        case .editFailed:
            .memoriesNoticeEditFailedTitle
        case .loadFailed, .draftSaveFailed:
            .commonLoadFailedTitle
        case .photoUploadFailed:
            .memoriesNoticePhotoFailedTitle
        case .deleteFailed:
            .memoriesNoticeDeleteFailedTitle
        case .noteFailed:
            .memoriesNoticeNoteFailedTitle
        case .memoryRemoved:
            .memoriesEditorRemovedTitle
        case .textTooLong:
            .memoriesNoticeTooLongTitle
        case .photoSaveDenied:
            .memoriesNoticePhotoSaveDeniedTitle
        case .photoSaveFailed, .photoSaved, .ownPartRemovedAfterJoin, .placeNotAddedAfterJoin:
            .memoriesNoticePhotoSaveFailedTitle
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .draftSaveFailed:
            .memoriesDraftSaveFailed
        case .photoUploadFailed:
            .memoriesNoticePhotoFailedMessage
        case .memoryRemoved:
            .memoriesNoticeMemoryRemovedMessage
        case .textTooLong:
            .memoriesNoticeTooLongMessage
        case .photoSaveDenied:
            .memoriesNoticePhotoSaveDeniedMessage
        case .ownPartRemovedAfterJoin:
            .memoriesNoticeOwnPartRemovedMessage
        case .placeNotAddedAfterJoin:
            .memoriesNoticePlaceNotAddedMessage
        case .createFailed, .editFailed, .loadFailed, .deleteFailed, .noteFailed, .photoSaveFailed, .photoSaved:
            .memoriesNoticeRetryMessage
        }
    }
}
