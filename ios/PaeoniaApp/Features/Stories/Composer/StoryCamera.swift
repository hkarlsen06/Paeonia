import AVFoundation
import SwiftUI
import UIKit

/// The camera behind the story composer's viewfinder. The capture session runs on its
/// own queue, because starting and stopping it blocks for a noticeable moment.
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
    // Touched only on `queue`.
    private var input: AVCaptureDeviceInput?
    private var isConfigured = false
    private var pendingCapture: CheckedContinuation<Data?, Never>?
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

    /// Switches between the back and front camera.
    func flip() {
        queue.async {
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
                // Turned and mirrored like the viewfinder.
                if let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelPreview,
                   connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = self.input?.device.position == .front
                }
                self.pendingCapture = continuation
                self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
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
        session.sessionPreset = .photo
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

/// The round white shutter button every camera app has.
struct StoryShutterButton: View {
    let isBusy: Bool
    let action: () -> Void

    /// The camera app's shutter size.
    private static let size: CGFloat = 78
    private static let ringWidth: CGFloat = 4
    /// The disc shrinks this much while the photo is taken.
    private static let pressedScale: CGFloat = 0.85

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: Self.ringWidth)
                    .frame(width: Self.size, height: Self.size)
                // The white disc sits inside the ring with a gap as wide as the ring.
                Circle()
                    .fill(.white)
                    .padding(Self.ringWidth * 2)
                    .frame(width: Self.size, height: Self.size)
                    .scaleEffect(isBusy ? Self.pressedScale : 1)
            }
            .contentShape(Circle())
            .shadow(color: .black.opacity(ThoughtBubbleMetrics.shadowOpacity), radius: PaeoniaSpacing.space8)
        }
        .buttonStyle(.plain)
        .animation(PaeoniaMotion.buttonPress, value: isBusy)
        .disabled(isBusy)
        .accessibilityLabel(Text(.storiesComposerTakePhoto))
    }
}
