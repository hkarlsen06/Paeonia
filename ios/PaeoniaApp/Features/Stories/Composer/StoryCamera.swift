import AVFoundation
import SwiftUI
import UIKit

/// The camera behind the story composer's viewfinder. It takes photos and records videos
/// of up to `Story.maxVideoDurationMs`. The capture session runs on its own queue,
/// because starting and stopping it blocks for a noticeable moment.
///
/// The microphone joins the session only while a video records, so the camera never
/// holds it (or the orange dot) while the person only looks. The app sets the audio
/// session itself through `DailyVoiceAudioSession`, which leaves a running call alone.
nonisolated final class StoryCamera: NSObject, @unchecked Sendable {
    /// What the viewfinder can show.
    enum Availability: Equatable, Sendable {
        case unknown
        case ready
        /// The person turned camera access off in Settings.
        case denied
        /// No camera, such as in the simulator.
        case unavailable
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "no.paeonia.story-camera")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    // Touched only on `queue`.
    private var input: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var pendingCapture: CheckedContinuation<Data?, Never>?
    private var recording = Recording.idle
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    /// Asks for camera access when needed and sets the session up with the back camera.
    func prepare() async -> Availability {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        default:
            return .denied
        }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.configure(position: .back) ? .ready : .unavailable)
            }
        }
    }

    func start() {
        queue.async {
            guard self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// Switches between the back and front camera. Not while a video records.
    func flip() {
        queue.async {
            guard case .idle = self.recording else { return }
            let next: AVCaptureDevice.Position = self.input?.device.position == .front ? .back : .front
            _ = self.configure(position: next)
        }
    }

    /// Keeps `layer` upright as the screen turns. An iPad turns with the device, an iPhone
    /// stays portrait.
    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        nonisolated(unsafe) let layer = layer
        queue.async {
            self.previewLayer = layer
            self.updateRotationCoordinator()
        }
    }

    /// Takes a photo as it looks in the viewfinder. Nil when the capture failed.
    func capture() async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.isConfigured, self.session.isRunning, self.pendingCapture == nil,
                      let connection = self.photoOutput.connection(with: .video)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                self.matchViewfinder(connection)
                self.pendingCapture = continuation
                self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    /// Records a video into `directory` and returns its file once the recording ends: on
    /// `stopRecording()`, at `Story.maxVideoDurationMs`, or when the system interrupts the
    /// camera, such as for a phone call or the app leaving the screen. An interrupted
    /// recording is kept when the file is usable. Nil when nothing usable was recorded.
    ///
    /// `withSound` adds the microphone. Without it, or during a call, the video is silent.
    func record(into directory: URL, withSound: Bool) async -> URL? {
        // Claimed before the audio setup, so a stop that comes during it is kept.
        guard await claimRecorder() else { return nil }
        var hasSound = withSound && !PaeoniaAudioSession.isCallActive
        if hasSound {
            do {
                try await DailyVoiceAudioSession.configureForRecording()
            } catch {
                hasSound = false
            }
        }
        defer {
            if hasSound { DailyVoiceAudioSession.deactivate() }
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(UUID().uuidString.lowercased()).mov")
        let withMicrophone = hasSound
        return await withCheckedContinuation { continuation in
            queue.async {
                self.startRecording(to: fileURL, withSound: withMicrophone, continuation: continuation)
            }
        }
    }

    /// Ends the recording. A recording runs at least `minimumRecording`, so a quick hold
    /// still makes a video that can be played.
    func stopRecording() {
        queue.async {
            switch self.recording {
            case .idle:
                break
            case .claimed:
                self.recording = .claimed(stopRequested: true)
            case let .starting(continuation, _):
                self.recording = .starting(continuation, stopRequested: true)
            case .recording:
                let elapsed = self.movieOutput.recordedDuration.seconds
                let remaining = elapsed.isFinite ? max(0, Self.minimumRecording - elapsed) : Self.minimumRecording
                self.queue.asyncAfter(deadline: .now() + remaining) {
                    if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
                }
            }
        }
    }

    private func claimRecorder() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.isConfigured, self.session.isRunning, case .idle = self.recording else {
                    continuation.resume(returning: false)
                    return
                }
                self.recording = .claimed(stopRequested: false)
                continuation.resume(returning: true)
            }
        }
    }

    private static let minimumRecording: TimeInterval = 1

    /// Runs on `queue`.
    private func startRecording(
        to fileURL: URL,
        withSound: Bool,
        continuation: CheckedContinuation<URL?, Never>
    ) {
        guard case let .claimed(stopRequested) = recording else {
            continuation.resume(returning: nil)
            return
        }
        guard session.isRunning, let connection = movieOutput.connection(with: .video) else {
            recording = .idle
            continuation.resume(returning: nil)
            return
        }
        recording = .starting(continuation, stopRequested: stopRequested)
        if withSound { addMicrophone() }
        movieOutput.connection(with: .audio)?.isEnabled = withSound && audioInput != nil
        matchViewfinder(connection)
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
    }

    /// Runs on `queue`. Adding an input pauses the preview for a moment, which is why it
    /// happens only for a recording.
    private func addMicrophone() {
        guard audioInput == nil,
              let device = AVCaptureDevice.default(for: .audio),
              let newInput = try? AVCaptureDeviceInput(device: device)
        else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(newInput) else { return }
        session.addInput(newInput)
        audioInput = newInput
    }

    /// Runs on `queue`.
    private func removeMicrophone() {
        guard let audioInput else { return }
        session.beginConfiguration()
        session.removeInput(audioInput)
        session.commitConfiguration()
        self.audioInput = nil
    }

    /// Runs on `queue`. Turns and mirrors the output like the viewfinder.
    private func matchViewfinder(_ connection: AVCaptureConnection) {
        if let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview,
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = input?.device.position == .front
        }
    }

    /// Runs on `queue`.
    private func finishRecording(_ fileURL: URL?) {
        let continuation: CheckedContinuation<URL?, Never>
        switch recording {
        case .idle, .claimed:
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
            return
        case let .starting(pending, _), let .recording(pending):
            continuation = pending
        }
        recording = .idle
        removeMicrophone()
        continuation.resume(returning: fileURL)
    }

    /// Runs on `queue`. Returns false when there is no camera for `position`.
    private func configure(position: AVCaptureDevice.Position) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let newInput = try? AVCaptureDeviceInput(device: device)
        else {
            return isConfigured
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // `.photo` can't record movies. Photos are made smaller before upload anyway.
        session.sessionPreset = .high
        // The app sets the audio session for a recording, so the camera never stops the
        // person's music or takes the session from a call.
        session.automaticallyConfiguresApplicationAudioSession = false
        if let input { session.removeInput(input) }
        guard session.canAddInput(newInput) else {
            if let input { session.addInput(input) }
            return isConfigured
        }
        session.addInput(newInput)
        input = newInput
        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
            movieOutput.maxRecordedDuration = CMTime(value: CMTimeValue(Story.maxVideoDurationMs), timescale: 1_000)
            session.addOutput(movieOutput)
        }
        isConfigured = true
        updateRotationCoordinator()
        return true
    }

    /// Runs on `queue`. The coordinator follows one camera, so a flip needs a new one.
    private func updateRotationCoordinator() {
        guard let device = input?.device, let previewLayer else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        nonisolated(unsafe) let layer = previewLayer
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { _, change in
            guard let angle = change.newValue else { return }
            DispatchQueue.main.async {
                layer.connection?.videoRotationAngle = angle
            }
        }
    }
}

extension StoryCamera {
    /// A recording from the moment it is asked for until its file is finished.
    private enum Recording {
        case idle
        /// `record` holds the recorder while it sets up the audio session. `stopRequested`
        /// when the finger lifted meanwhile.
        case claimed(stopRequested: Bool)
        /// The output was asked to record and the file has not begun.
        case starting(CheckedContinuation<URL?, Never>, stopRequested: Bool)
        case recording(CheckedContinuation<URL?, Never>)
    }
}

extension StoryCamera: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from _: [AVCaptureConnection]) {
        queue.async {
            guard case let .starting(continuation, stopRequested) = self.recording else { return }
            self.recording = .recording(continuation)
            if stopRequested { self.stopRecording() }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: Error?
    ) {
        // The 60 second limit, an interruption or a full disk end the recording with an
        // error, and the file is still whole when the output says it finished.
        let finished = error == nil
            || (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        if !finished { try? FileManager.default.removeItem(at: outputFileURL) }
        queue.async {
            self.finishRecording(finished ? outputFileURL : nil)
        }
    }
}

extension StoryCamera: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async {
            self.pendingCapture?.resume(returning: data)
            self.pendingCapture = nil
        }
    }
}

/// The live camera image, filling its frame.
struct StoryCameraPreview: UIViewRepresentable {
    let camera: StoryCamera

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        camera.attach(view.previewLayer)
        return view
    }

    func updateUIView(_: PreviewView, context _: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
