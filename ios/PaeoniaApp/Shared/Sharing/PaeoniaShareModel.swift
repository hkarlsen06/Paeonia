import Observation
import UIKit

/// Prepares one picture for `PaeoniaShareSheet` and saves it to Photos. The
/// picture is made once, so the preview, the share sheet and the saved copy are
/// the same image.
@MainActor
@Observable
final class PaeoniaShareModel {
    enum Phase {
        case preparing
        case ready(PaeoniaShareImage, preview: UIImage)
        case failed
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed
    }

    let shareable: PaeoniaShareable
    private(set) var phase = Phase.preparing
    private(set) var saveState = SaveState.idle
    /// The person turned off photo access, so saving needs a trip to Settings.
    var isShowingPermissionAlert = false

    @ObservationIgnored private let saver: any PhotoLibrarySaving

    init(shareable: PaeoniaShareable, saver: any PhotoLibrarySaving = PhotoLibrarySaver()) {
        self.shareable = shareable
        self.saver = saver
    }

    var isReady: Bool {
        if case .ready = phase { true } else { false }
    }

    /// Makes the picture. Does nothing once it is ready.
    func prepare() async {
        if case .ready = phase { return }
        phase = .preparing
        let image = await shareable.makeImage()
        guard !Task.isCancelled else { return }
        if let image, let preview = UIImage(data: image.data) {
            phase = .ready(image, preview: preview)
        } else {
            phase = .failed
        }
    }

    func save() async {
        guard case let .ready(image, _) = phase, saveState != .saving, saveState != .saved else { return }
        saveState = .saving
        switch await saver.saveImage(image.data) {
        case .saved:
            saveState = .saved
            PaeoniaHaptics.drawingSaved()
        case .permissionDenied:
            saveState = .idle
            isShowingPermissionAlert = true
        case .failed:
            saveState = .failed
            PaeoniaHaptics.validationError()
        }
    }
}
