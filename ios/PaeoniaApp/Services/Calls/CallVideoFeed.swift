import AVFoundation
import CoreMedia
import UIKit
@preconcurrency import LiveKitWebRTC

/// One side's video. WebRTC hands it frames on its own thread, and it shows each frame in every
/// view made from it. The views draw with `AVSampleBufferDisplayLayer`, which keeps drawing in the
/// background, so the same frames can feed system Picture in Picture.
nonisolated final class CallVideoFeed: NSObject, LKRTCVideoRenderer, @unchecked Sendable {
    /// Only touched on WebRTC's render thread.
    private var pool: CVPixelBufferPool?
    private var poolSize: (width: Int, height: Int) = (0, 0)

    @MainActor private var views: [WeakVideoView] = []
    @MainActor private var isMirrored = false {
        didSet {
            for view in liveViews { view.isMirrored = isMirrored }
        }
    }
    /// A camera is starting, so frames from the one before it wait out the switch instead of
    /// showing with the new camera's mirroring.
    @MainActor private var isWaitingForCamera = false

    /// The upright size of the latest frame, such as for Picture in Picture's window.
    @MainActor var onFrameSize: ((CGSize) -> Void)?
    @MainActor private var frameSize: CGSize = .zero

    /// True when frames stop for longer than `CallFrameGaps` allows, false when they come again.
    /// Reported only while `watchForStalls(true)` is on.
    @MainActor var onStallChange: ((Bool) -> Void)?
    @MainActor private var gaps = CallFrameGaps()
    @MainActor private var isStalled = false
    @MainActor private var stallWatch: Task<Void, Never>?

    @MainActor
    func makeView() -> CallVideoLayerView {
        let view = CallVideoLayerView()
        view.isMirrored = isMirrored
        views.removeAll { $0.view == nil }
        views.append(WeakVideoView(view: view))
        return view
    }

    /// Empties every view, such as when a call ends.
    @MainActor
    func clear() {
        watchForStalls(false)
        for view in liveViews { view.flush() }
        frameSize = .zero
    }

    /// Watches for frames that stop coming, such as while the partner's camera is on. Each start
    /// waits for a first frame, so a camera that is still starting does not count as stalled.
    @MainActor
    func watchForStalls(_ isOn: Bool) {
        guard isOn != (stallWatch != nil) else { return }
        stallWatch?.cancel()
        stallWatch = nil
        gaps = CallFrameGaps()
        setStalled(false)
        guard isOn else { return }
        stallWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                setStalled(gaps.isStalled(at: ProcessInfo.processInfo.systemUptime))
            }
        }
    }

    @MainActor
    private func setStalled(_ stalled: Bool) {
        guard stalled != isStalled else { return }
        isStalled = stalled
        onStallChange?(stalled)
    }

    @MainActor private var liveViews: [CallVideoLayerView] {
        views.compactMap(\.view)
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: LKRTCVideoFrame?) {
        guard let frame, let sample = sampleBuffer(for: frame) else { return }
        let rotation = frame.rotation
        let isQuarterTurn = rotation == ._90 || rotation == ._270
        let size = isQuarterTurn
            ? CGSize(width: Int(frame.height), height: Int(frame.width))
            : CGSize(width: Int(frame.width), height: Int(frame.height))
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.show(sample, rotation: rotation, size: size)
            }
        }
    }

    /// Holds the picture still while the camera switches.
    @MainActor
    func cameraWillStart() {
        isWaitingForCamera = true
    }

    /// The new camera sends now. A front camera shows mirrored, like a mirror.
    @MainActor
    func cameraStarted(isMirrored: Bool) {
        self.isMirrored = isMirrored
        isWaitingForCamera = false
    }

    @MainActor
    private func show(_ sample: CallVideoSample, rotation: LKRTCVideoRotation, size: CGSize) {
        guard !isWaitingForCamera else { return }
        if stallWatch != nil {
            gaps.frameArrived(at: ProcessInfo.processInfo.systemUptime)
            setStalled(false)
        }
        if size != frameSize {
            frameSize = size
            onFrameSize?(size)
        }
        for view in liveViews {
            view.enqueue(sample, rotation: rotation)
        }
    }

    private func sampleBuffer(for frame: LKRTCVideoFrame) -> CallVideoSample? {
        guard let pixelBuffer = pixelBuffer(for: frame) else { return nil }
        var sample = CMReadySampleBuffer(
            pixelBuffer: CVReadOnlyPixelBuffer(unsafeBuffer: pixelBuffer),
            presentationTimeStamp: CMTime(value: frame.timeStampNs, timescale: 1_000_000_000)
        )
        // The renderer's synchronizer never runs, so each frame shows as soon as it arrives.
        sample.sampleAttachments.displayImmediately = true
        return CallVideoSample(sample)
    }

    private func pixelBuffer(for frame: LKRTCVideoFrame) -> CVPixelBuffer? {
        if let buffer = frame.buffer as? LKRTCCVPixelBuffer {
            return buffer.pixelBuffer
        }
        // Software decoders (VP8, VP9, AV1) give planar I420 frames. The display layer takes NV12.
        return nv12Buffer(from: frame.buffer.toI420())
    }

    private func nv12Buffer(from source: any LKRTCI420BufferProtocol) -> CVPixelBuffer? {
        let width = Int(source.width)
        let height = Int(source.height)
        guard let pool = pool(width: width, height: height) else { return nil }
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess, let output else {
            return nil
        }
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(output, 0),
              let chromaBase = CVPixelBufferGetBaseAddressOfPlane(output, 1)
        else {
            return nil
        }
        let luma = lumaBase.assumingMemoryBound(to: UInt8.self)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(output, 0)
        for row in 0..<height {
            (luma + row * lumaStride).update(from: source.dataY + row * Int(source.strideY), count: width)
        }
        let chroma = chromaBase.assumingMemoryBound(to: UInt8.self)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(output, 1)
        for row in 0..<Int(source.chromaHeight) {
            let line = chroma + row * chromaStride
            let blue = source.dataU + row * Int(source.strideU)
            let red = source.dataV + row * Int(source.strideV)
            for column in 0..<Int(source.chromaWidth) {
                line[column * 2] = blue[column]
                line[column * 2 + 1] = red[column]
            }
        }
        return output
    }

    private func pool(width: Int, height: Int) -> CVPixelBufferPool? {
        if let pool, poolSize == (width, height) {
            return pool
        }
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var created: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &created)
        pool = created
        poolSize = (width, height)
        return created
    }

    private struct WeakVideoView {
        weak var view: CallVideoLayerView?
    }
}

/// When a video's frames have stopped long enough that its last frame would stand still. A gap
/// counts from 1 second, or from 3 times the usual gap between frames when the video is slow, up
/// to 3 seconds, so video that runs at 1 or 2 frames a second on a weak connection is not
/// called stalled between each frame. The freeze count in WebRTC's stats also starts from 3 times
/// the average gap over the last 30 frames, with a floor of the average plus 150 ms, which suits a
/// counter more than a blur on screen.
nonisolated struct CallFrameGaps {
    static let minStall: TimeInterval = 1
    static let maxStall: TimeInterval = 3
    static let averagedFrames = 30

    private var lastFrame: TimeInterval?
    private var intervals: [TimeInterval] = []

    mutating func frameArrived(at time: TimeInterval) {
        if let lastFrame {
            intervals.append(time - lastFrame)
            if intervals.count > Self.averagedFrames {
                intervals.removeFirst()
            }
        }
        lastFrame = time
    }

    /// Nothing is stalled before the first frame.
    func isStalled(at time: TimeInterval) -> Bool {
        guard let lastFrame else { return false }
        return time - lastFrame >= threshold
    }

    private var threshold: TimeInterval {
        guard !intervals.isEmpty else { return Self.minStall }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        return min(max(3 * average, Self.minStall), Self.maxStall)
    }
}

typealias CallVideoSample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>

/// Shows one side's video, filled to its bounds and turned the way the sender held the phone.
final class CallVideoLayerView: UIView {
    /// Called when the view enters or leaves a window, so Picture in Picture can follow the
    /// partner's video on screen.
    var onWindowChange: (() -> Void)?
    var isMirrored = false {
        didSet { setNeedsLayout() }
    }

    private let displayLayer: AVSampleBufferDisplayLayer
    /// The display layer's renderer takes frames only through a synchronizer's receiver.
    private let synchronizer: AVSampleBufferRenderSynchronizer
    private let receiver: AVSampleBufferVideoRenderer.Receiver
    private var rotation: LKRTCVideoRotation = ._0

    override init(frame: CGRect) {
        let displayLayer = AVSampleBufferDisplayLayer()
        let synchronizer = AVSampleBufferRenderSynchronizer()
        receiver = synchronizer.sampleBufferReceiver(adding: displayLayer.sampleBufferRenderer)
        self.displayLayer = displayLayer
        self.synchronizer = synchronizer
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false
        displayLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(displayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let isQuarterTurn = rotation == ._90 || rotation == ._270
        displayLayer.bounds = CGRect(
            origin: .zero,
            size: isQuarterTurn ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        )
        displayLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        var transform = CATransform3DMakeRotation(CGFloat(rotation.rawValue) * .pi / 180, 0, 0, 1)
        if isMirrored {
            transform = CATransform3DConcat(transform, CATransform3DMakeScale(-1, 1, 1))
        }
        displayLayer.transform = transform
        CATransaction.commit()
    }

    func enqueue(_ sample: CallVideoSample, rotation: LKRTCVideoRotation) {
        if rotation != self.rotation {
            self.rotation = rotation
            setNeedsLayout()
        }
        switch receiver.enqueueImmediately(sample) {
        case .cancelledDueToFlushRequiredToResume, .cancelledDueToError:
            // The renderer stops after the app was in the background. A flush starts it again.
            receiver.flush()
            _ = receiver.enqueueImmediately(sample)
        default:
            break
        }
    }

    func flush() {
        Task { await receiver.flush(removingDisplayedImage: true) }
    }
}
