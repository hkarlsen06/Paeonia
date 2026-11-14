import AVFoundation
import CoreMedia
import UIKit
@preconcurrency import WebRTC

/// One side's video. WebRTC hands it frames on its own thread, and it shows each frame in every
/// view made from it. The views draw with `AVSampleBufferDisplayLayer`, which keeps drawing in the
/// background, so the same frames can feed system Picture in Picture.
nonisolated final class CallVideoFeed: NSObject, RTCVideoRenderer, @unchecked Sendable {
    /// Only touched on WebRTC's render thread.
    private var pool: CVPixelBufferPool?
    private var poolSize: (width: Int, height: Int) = (0, 0)

    @MainActor private var views: [WeakVideoView] = []
    @MainActor var isMirrored = false {
        didSet {
            for view in liveViews { view.isMirrored = isMirrored }
        }
    }

    /// The upright size of the latest frame, such as for Picture in Picture's window.
    @MainActor var onFrameSize: ((CGSize) -> Void)?
    @MainActor private var frameSize: CGSize = .zero

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
        for view in liveViews { view.flush() }
        frameSize = .zero
    }

    @MainActor private var liveViews: [CallVideoLayerView] {
        views.compactMap(\.view)
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
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

    @MainActor
    private func show(_ sample: CallVideoSample, rotation: RTCVideoRotation, size: CGSize) {
        if size != frameSize {
            frameSize = size
            onFrameSize?(size)
        }
        for view in liveViews {
            view.enqueue(sample, rotation: rotation)
        }
    }

    private func sampleBuffer(for frame: RTCVideoFrame) -> CallVideoSample? {
        guard let pixelBuffer = pixelBuffer(for: frame) else { return nil }
        var sample = CMReadySampleBuffer(
            pixelBuffer: CVReadOnlyPixelBuffer(unsafeBuffer: pixelBuffer),
            presentationTimeStamp: CMTime(value: frame.timeStampNs, timescale: 1_000_000_000)
        )
        // The renderer's synchronizer never runs, so each frame shows as soon as it arrives.
        sample.sampleAttachments.displayImmediately = true
        return CallVideoSample(sample)
    }

    private func pixelBuffer(for frame: RTCVideoFrame) -> CVPixelBuffer? {
        if let buffer = frame.buffer as? RTCCVPixelBuffer {
            return buffer.pixelBuffer
        }
        // Software decoders (VP8, VP9, AV1) give planar I420 frames. The display layer takes NV12.
        return nv12Buffer(from: frame.buffer.toI420())
    }

    private func nv12Buffer(from source: any RTCI420BufferProtocol) -> CVPixelBuffer? {
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

typealias CallVideoSample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>

/// Shows one side's video, filled to its bounds and turned the way the sender held the phone.
final class CallVideoLayerView: UIView {
    /// Called when the view enters or leaves a window, so Picture in Picture can follow the
    /// partner's video on screen.
    var onWindowChange: ((CallVideoLayerView) -> Void)?
    var isMirrored = false {
        didSet { setNeedsLayout() }
    }

    private let displayLayer: AVSampleBufferDisplayLayer
    /// The display layer's renderer takes frames only through a synchronizer's receiver.
    private let synchronizer: AVSampleBufferRenderSynchronizer
    private let receiver: AVSampleBufferVideoRenderer.Receiver
    private var rotation: RTCVideoRotation = ._0

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
        onWindowChange?(self)
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

    func enqueue(_ sample: CallVideoSample, rotation: RTCVideoRotation) {
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
