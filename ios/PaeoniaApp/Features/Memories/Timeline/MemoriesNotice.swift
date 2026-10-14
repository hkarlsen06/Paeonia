import Foundation

/// An outcome of a memory action, shown through the shared top banner. Copy says what
/// happened in plain words; the underlying error is logged in debug builds only.
enum MemoriesNotice: Equatable {
    case createFailed
    case editFailed
    case photoUploadFailed
    case deleteFailed
    case noteFailed
    /// The partner deleted the memory while this person was changing it.
    case memoryRemoved
    /// The title or note is longer than the server accepts.
    case textTooLong
    case photoSaved
    case photoSaveDenied
    case photoSaveFailed

    var banner: PaeoniaBannerContent {
        switch self {
        case .photoSaved:
            .info(message: String(localized: .memoriesNoticePhotoSavedMessage))
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
        case .photoSaveFailed, .photoSaved:
            .memoriesNoticePhotoSaveFailedTitle
        }
    }

    private var message: LocalizedStringResource {
        switch self {
        case .photoUploadFailed:
            .memoriesNoticePhotoFailedMessage
        case .memoryRemoved:
            .memoriesNoticeMemoryRemovedMessage
        case .textTooLong:
            .memoriesNoticeTooLongMessage
        case .photoSaveDenied:
            .memoriesNoticePhotoSaveDeniedMessage
        case .createFailed, .editFailed, .deleteFailed, .noteFailed, .photoSaveFailed, .photoSaved:
            .memoriesNoticeRetryMessage
        }
    }
}
