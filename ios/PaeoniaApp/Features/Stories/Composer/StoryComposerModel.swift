import AVFoundation
import Observation
import PhotosUI
import SwiftUI

/// The story composer's camera, shutter and chosen photo or video.
///
/// A tap on the shutter takes a photo. Holding it past `holdThreshold` records a video
/// until the finger lifts, `Story.maxVideoDurationMs` passes or the system interrupts the
/// camera. A recorded or picked video is made ready for upload (`VideoPreparation`) in
/// `directory`, and every file there is deleted when the composer closes.
@Observable
final class StoryComposerModel {
    enum Shutter: Equatable {
        case idle
        /// The finger is down and has not been held long enough for a video.
        case pressed
        case takingPhoto
        /// Waiting for the answer to the microphone question.
        case startingVideo
        case recording(since: Date)
    }

    enum Media {
        case photo(Data, preview: UIImage)
        case video(PreparedVideo)
    }

    /// A camera recording on its way to becoming a story video. It is the only copy.
    struct Recording {
        let fileURL: URL
        /// Taken when the recording ended, so a privacy purge since then drops it.
        let ticket: VideoPreparation.Ticket
    }

    let camera = StoryCamera()
    /// The one player for the chosen video's muted, looping preview.
    let previewPlayer = StoryLoopingPlayer()
    private(set) var availability: StoryCamera.Availability = .unknown
    private(set) var shutter = Shutter.idle
    private(set) var media: Media?
    /// A picked photo or video is loading, or a video is being made ready.
    private(set) var isPreparing = false
    /// A recording that could not be made ready. It stays until the person tries again or
    /// deletes it, because nothing else holds the video.
    private(set) var failedRecording: Recording?
    /// Shows an error or a notice to the person.
    @ObservationIgnored var onMessage: (PaeoniaBannerContent) -> Void = { _ in }

    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    @ObservationIgnored private var isAppActive = true
    @ObservationIgnored private var isClosed = false
    @ObservationIgnored private var hasExplainedSilentVideo = false

    /// A touch held this long is a video, not a photo.
    static let holdThreshold: Duration = .milliseconds(300)

    /// Where the composer keeps recordings and prepared videos. Inside the outgoing media
    /// folder, so the privacy purge clears it too.
    nonisolated static func directory() -> URL {
        PreparedVideo.outgoingMediaDirectoryURL().appendingPathComponent("stories", isDirectory: true)
    }

    /// The viewfinder dims while a photo is taken or a video is made ready.
    var isDimmed: Bool {
        isPreparing || shutter == .takingPhoto || failedRecording != nil
    }

    /// Only Cancel may throw away what the composer holds: a photo or video, one being
    /// recorded or made ready, or a recording that failed.
    var holdsMedia: Bool {
        media != nil || shutter != .idle || isPreparing || failedRecording != nil
    }

    var isRecording: Bool {
        if case .recording = shutter { true } else { false }
    }

    // MARK: - Lifecycle

    /// Clears files a closed or crashed composer left behind, then sets the camera up. It
    /// asks for the microphone here too, because the question would end the first hold on
    /// the shutter before it records.
    func open() async {
        await Self.deleteFiles()
        availability = await camera.prepare()
        if availability == .ready, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
    }

    /// Stops everything and deletes every file this composer made. A post that went
    /// through already copied its video into `VideoFileCache`.
    func close() {
        isClosed = true
        holdTask?.cancel()
        prepareTask?.cancel()
        camera.stopRecording()
        camera.stop()
        previewPlayer.stop()
        Task.detached { await Self.deleteFiles() }
    }

    /// The camera runs only while the viewfinder shows and the app is in front.
    func updateCamera(isAppActive: Bool) {
        self.isAppActive = isAppActive
        if media == nil, !isPreparing, failedRecording == nil, availability == .ready, isAppActive {
            camera.start()
        } else {
            camera.stop()
        }
    }

    // MARK: - Shutter

    func pressBegan() {
        guard shutter == .idle, media == nil, !isPreparing, failedRecording == nil else { return }
        shutter = .pressed
        holdTask = Task {
            try? await Task.sleep(for: Self.holdThreshold)
            guard !Task.isCancelled, shutter == .pressed else { return }
            await recordVideo()
        }
    }

    /// Also runs when the system cancels the touch, such as for the microphone question.
    func pressEnded() {
        switch shutter {
        case .pressed:
            holdTask?.cancel()
            shutter = .idle
            Task { await takePhoto() }
        case .startingVideo:
            // Still waiting for the microphone answer. Nothing records until the person holds again.
            shutter = .idle
        case .recording:
            stopRecording()
        case .idle, .takingPhoto:
            break
        }
    }

    func takePhoto() async {
        guard shutter == .idle, media == nil, failedRecording == nil else { return }
        shutter = .takingPhoto
        let data = await camera.capture()
        shutter = .idle
        if let data {
            PaeoniaHaptics.selection()
            setPhoto(data)
        } else {
            onMessage(.error(message: String(localized: .storiesErrorPhotoUnreadable)))
        }
    }

    /// Records until `stopRecording()`. When the microphone question shows first, it records
    /// after the answer only if nothing ended the hold meanwhile, such as VoiceOver's record action.
    func recordVideo() async {
        guard shutter == .idle || shutter == .pressed, media == nil, failedRecording == nil else { return }
        shutter = .startingVideo
        let withSound = await microphoneForRecording()
        guard shutter == .startingVideo, !isClosed else { return }
        shutter = .recording(since: .now)
        PaeoniaHaptics.selection()
        let file = await camera.record(into: Self.directory(), withSound: withSound)
        shutter = .idle
        guard !isClosed else {
            if let file { try? FileManager.default.removeItem(at: file) }
            return
        }
        guard let file else {
            onMessage(.error(message: String(localized: .storiesErrorRecordingFailed)))
            return
        }
        PaeoniaHaptics.selection()
        prepareVideo(Recording(fileURL: file, ticket: VideoPreparation.ticket()))
    }

    func stopRecording() {
        camera.stopRecording()
    }

    /// Whether the next video records sound, after asking when the person has not answered yet.
    private func microphoneForRecording() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return true }
        default:
            break
        }
        if !hasExplainedSilentVideo {
            hasExplainedSilentVideo = true
            onMessage(.info(message: String(localized: .storiesComposerNoMicrophone), systemImage: "mic.slash"))
        }
        return false
    }

    // MARK: - Media

    func loadPicked(_ item: PhotosPickerItem) {
        isPreparing = true
        camera.stop()
        if item.isVideo {
            let ticket = VideoPreparation.ticket()
            prepareTask = Task {
                do {
                    show(try await VideoPreparation.prepare(
                        item, into: Self.directory(), cap: .oneMinute, ticket: ticket
                    ))
                } catch {
                    finishPreparing(failure: error)
                }
            }
        } else {
            prepareTask = Task {
                let data = try? await item.loadTransferable(type: Data.self)
                guard !isClosed else { return }
                isPreparing = false
                if let data {
                    setPhoto(data)
                } else {
                    onMessage(.error(message: String(localized: .storiesErrorPhotoUnreadable)))
                    updateCamera(isAppActive: isAppActive)
                }
            }
        }
    }

    /// Prepares a failed recording again.
    func retryFailedRecording() {
        guard let recording = failedRecording else { return }
        failedRecording = nil
        prepareVideo(recording)
    }

    /// Deletes a failed recording and goes back to the viewfinder.
    func deleteFailedRecording() {
        guard let recording = failedRecording else { return }
        failedRecording = nil
        try? FileManager.default.removeItem(at: recording.fileURL)
        updateCamera(isAppActive: isAppActive)
    }

    /// Back to the viewfinder. A video's file is deleted.
    func removeMedia() {
        if case let .video(video) = media {
            try? FileManager.default.removeItem(at: video.fileURL)
        }
        previewPlayer.stop()
        media = nil
        updateCamera(isAppActive: isAppActive)
    }

    /// What the view model posts.
    var postMedia: StoryPostMedia? {
        switch media {
        case let .photo(data, _): .photo(data)
        case let .video(video): .video(video)
        case nil: nil
        }
    }

    private func setPhoto(_ data: Data) {
        Task {
            let image = await MemoryImageDecoding.downsample(data, maxPixelSize: StoryPhotoView.maxPixelSize)
            guard !isClosed else { return }
            guard let image else {
                onMessage(.error(message: String(localized: .storiesErrorPhotoUnreadable)))
                updateCamera(isAppActive: isAppActive)
                return
            }
            media = .photo(data, preview: image)
            updateCamera(isAppActive: isAppActive)
        }
    }

    /// Makes a recording ready to upload, then deletes it. `VideoPreparation` tries again
    /// when the app left during the work. A recording that still fails is kept for the
    /// person to try again or delete, unless it is too long or a privacy purge removed it.
    private func prepareVideo(_ recording: Recording) {
        isPreparing = true
        camera.stop()
        prepareTask = Task {
            do {
                show(try await VideoPreparation.prepare(
                    source: recording.fileURL, into: Self.directory(), cap: .oneMinute, ticket: recording.ticket,
                    keepsSourceOnFailure: true
                ))
            } catch {
                let isKept = !isClosed && !(error is CancellationError) && error as? VideoTranscodeError != .tooLong
                guard !isKept else {
                    isPreparing = false
                    failedRecording = recording
                    return
                }
                try? FileManager.default.removeItem(at: recording.fileURL)
                finishPreparing(failure: error)
            }
        }
    }

    private func show(_ video: PreparedVideo) {
        guard !isClosed, !Task.isCancelled else {
            try? FileManager.default.removeItem(at: video.fileURL)
            return
        }
        media = .video(video)
        previewPlayer.play(video.fileURL)
        finishPreparing(failure: nil)
    }

    private func finishPreparing(failure: (any Error)?) {
        isPreparing = false
        guard !isClosed else { return }
        if let message = failure.flatMap({ VideoLengthCap.oneMinute.message(for: $0) }) {
            onMessage(.error(message: String(localized: message)))
        }
        updateCamera(isAppActive: isAppActive)
    }

    @concurrent
    private nonisolated static func deleteFiles() async {
        try? FileManager.default.removeItem(at: directory())
    }
}

/// Plays one video muted and on a loop, for the composer's preview. It lives in the
/// model, outside the view body, so a redraw never makes a new player.
final class StoryLoopingPlayer {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init() {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    func play(_ fileURL: URL) {
        stop()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: fileURL))
        player.play()
    }

    func stop() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }
}
