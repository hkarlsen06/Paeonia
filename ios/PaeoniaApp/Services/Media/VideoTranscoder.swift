import AVFoundation
import CoreMedia
import VideoToolbox

/// A video ready to upload: an HEVC mp4 whose frames are upright, so `width` and
/// `height` are the size it shows at.
nonisolated struct PreparedVideo: Sendable, Equatable {
    let fileURL: URL
    let width: Int
    let height: Int
    let durationMs: Int
    let byteSize: Int64

    /// Where prepared videos and chat GIFs wait until they are sent. Application Support
    /// survives a restart while the outbox retries, and the privacy purge clears it with the
    /// other unsent drafts.
    static func outgoingMediaDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OutgoingMedia", isDirectory: true)
    }
}

nonisolated enum VideoTranscodeError: Error, Equatable, Sendable {
    /// The video is longer than the caller allows, by more than `durationToleranceMs`.
    /// Nothing was written.
    case tooLong
    /// The file has no video the phone can read.
    case unreadable
    /// Reading or writing stopped partway. Nothing was kept.
    case failed
}

/// Turns a video from the library or the camera into a small mp4 with a fixed bitrate.
/// AVAssetExportSession presets have no bitrate control and made 56 to 66 MB a minute,
/// so this reads and writes the frames itself.
///
/// HDR video (HLG, Dolby Vision) is tone mapped to SDR Rec.709 by the video composition.
/// Without explicit color properties, the conversion washes the colors out.
nonisolated enum VideoTranscoder {
    static let maxLongSide = 1_280
    static let maxFramesPerSecond = 30
    static let videoBitsPerSecond = 2_500_000
    static let audioBitsPerSecond = 128_000
    static let audioSampleRate = 44_100
    /// A clip the camera stopped at the limit, or one the Photos editor trimmed to it, can run
    /// a few hundred milliseconds over. Such a clip is cut to the limit instead of refused.
    static let durationToleranceMs = 500

    /// Writes a new mp4 into `directory` and returns it. Throws `.tooLong` before any
    /// work when the source runs longer than `maxDurationMs` plus `durationToleranceMs`,
    /// and cuts a source within the tolerance to exactly `maxDurationMs`. A failed or
    /// cancelled run deletes its partial file.
    @concurrent
    static func transcode(_ sourceURL: URL, into directory: URL, maxDurationMs: Int) async throws -> PreparedVideo {
        let asset = AVURLAsset(url: sourceURL)
        var source: SourceVideo
        do {
            source = try await SourceVideo(asset)
        } catch {
            if error is CancellationError { throw error }
            throw error as? VideoTranscodeError ?? .unreadable
        }
        guard source.durationMs <= maxDurationMs + durationToleranceMs else { throw VideoTranscodeError.tooLong }
        if source.durationMs > maxDurationMs {
            source.cut(to: maxDurationMs)
        }
        try Task.checkCancellation()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("\(UUID().uuidString.lowercased()).mp4")
        do {
            try await write(source, from: asset, to: outputURL)
            let output = AVURLAsset(url: outputURL)
            let duration = try await output.load(.duration)
            let byteSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64
            return PreparedVideo(
                fileURL: outputURL,
                width: source.outputWidth,
                height: source.outputHeight,
                // The last audio packet can end a few milliseconds after the cut.
                durationMs: min(milliseconds(duration), maxDurationMs),
                byteSize: byteSize ?? 0
            )
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw error as? VideoTranscodeError ?? .failed
        }
    }

    private static func write(_ source: SourceVideo, from asset: AVURLAsset, to outputURL: URL) async throws {
        let reader = try AVAssetReader(asset: asset)
        if source.isCut {
            reader.timeRange = CMTimeRange(start: .zero, duration: source.duration)
        }
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [source.videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        videoOutput.videoComposition = source.composition()
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: source.videoSettings())
        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else { throw VideoTranscodeError.failed }
        // Asking for a provider or a receiver adds the output or the input.
        let videoPump = Pump(
            provider: reader.outputProvider(for: videoOutput),
            receiver: writer.inputReceiver(for: videoInput)
        )

        var audioPump: Pump?
        if let audioTrack = source.audioTrack {
            let output = AVAssetReaderAudioMixOutput(audioTracks: [audioTrack], audioSettings: source.pcmSettings())
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: source.aacSettings())
            guard reader.canAdd(output), writer.canAdd(input) else { throw VideoTranscodeError.failed }
            audioPump = Pump(provider: reader.outputProvider(for: output), receiver: writer.inputReceiver(for: input))
        }

        do {
            try reader.start()
            try writer.start()
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw VideoTranscodeError.failed
        }
        writer.startSession(atSourceTime: .zero)
        try await pump(videoPump, audioPump, from: reader, to: writer, endingAt: source.isCut ? source.duration : nil)
    }

    /// Moves every sample, then finishes the file. A cut source ends the file at `end`.
    private static func pump(
        _ videoPump: sending Pump,
        _ audioPump: sending Pump?,
        from reader: AVAssetReader,
        to writer: AVAssetWriter,
        endingAt end: CMTime?
    ) async throws {
        let stopper = Stopper(writer: writer)
        async let video: Void = videoPump.run(stopper: stopper)
        async let audio: Void? = audioPump?.run(stopper: stopper)
        var failure: (any Error)?
        do { try await video } catch { failure = error }
        do { _ = try await audio } catch { failure = failure ?? error }
        guard failure == nil, reader.status == .completed else {
            stopper.stop()
            // Only now that both pumps finished. `cancelReading` while a pump waits in
            // `next()` crashed in AVFoundation.
            reader.cancelReading()
            throw failure ?? VideoTranscodeError.failed
        }
        // A cancel that comes after the last sample must not cancel the writer while it
        // finishes, which throws an exception.
        guard stopper.beginFinishing() else { throw CancellationError() }
        if let end {
            writer.endSession(atSourceTime: end)
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw VideoTranscodeError.failed }
    }

    fileprivate static func milliseconds(_ time: CMTime) -> Int {
        guard time.isNumeric else { return 0 }
        return Int((time.seconds * 1_000).rounded())
    }
}

/// Moves one track's samples from the reader to the writer. The receiver waits until
/// the writer wants more, so the video and audio pumps interleave on their own.
nonisolated private final class Pump {
    let provider: AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>>
    let receiver: AVAssetWriterInput.SampleBufferReceiver

    init(
        provider: sending AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>>,
        receiver: sending AVAssetWriterInput.SampleBufferReceiver
    ) {
        self.provider = provider
        self.receiver = receiver
    }

    /// A pump that stops early stops the writer through `stopper`. Otherwise the other
    /// pump waits in `append` for good, because the writer waits for this track's samples.
    func run(stopper: Stopper) async throws {
        do {
            try await withTaskCancellationHandler {
                while let sample = try await provider.next() {
                    try Task.checkCancellation()
                    try await receiver.append(sample)
                }
            } onCancel: {
                // `cancelWriting` blocks until the writer's queue stops, and that queue may be
                // resuming this task. Called inside the cancel handler, it deadlocked.
                DispatchQueue.global(qos: .userInitiated).async { stopper.stop() }
            }
            receiver.finish()
        } catch {
            stopper.stop()
            throw error
        }
    }
}

/// `cancelWriting` may run on any thread while the pumps wait, which is what unblocks
/// them, so this box crosses tasks. It runs once. A second `stop` waits for the first to
/// finish, so the caller may delete the output file once it returns.
nonisolated private final class Stopper: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let lock = NSLock()
    private var isStopped = false

    init(writer: AVAssetWriter) {
        self.writer = writer
    }

    func stop() {
        lock.withLock {
            guard !isStopped else { return }
            isStopped = true
            writer.cancelWriting()
        }
    }

    /// Makes later `stop` calls do nothing. False when the writer was already stopped.
    func beginFinishing() -> Bool {
        lock.withLock {
            guard !isStopped else { return false }
            isStopped = true
            return true
        }
    }
}

/// What the transcoder needs to know about the source, read once.
nonisolated private struct SourceVideo {
    let videoTrack: AVAssetTrack
    let audioTrack: AVAssetTrack?
    private(set) var duration: CMTime
    private(set) var durationMs: Int
    /// Whether the output stops before the source ends.
    private(set) var isCut = false
    let outputWidth: Int
    let outputHeight: Int
    let framesPerSecond: Int
    let audioChannels: Int
    /// The track's rotation, moved into positive coordinates and scaled to the output.
    let transform: CGAffineTransform

    init(_ asset: AVURLAsset) async throws {
        let duration = try await asset.load(.duration)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoTranscodeError.unreadable
        }
        let (naturalSize, preferredTransform, nominalFrameRate) = try await videoTrack.load(
            .naturalSize, .preferredTransform, .nominalFrameRate
        )
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

        // `naturalSize` ignores rotation. The transform turns a portrait clip stored
        // landscape upright, and may move it to negative coordinates.
        let displayed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let longSide = max(abs(displayed.width), abs(displayed.height))
        guard longSide > 0 else { throw VideoTranscodeError.unreadable }
        let scale = min(1, CGFloat(VideoTranscoder.maxLongSide) / longSide)
        // HEVC wants even dimensions.
        let width = max(2, Int((abs(displayed.width) * scale / 2).rounded()) * 2)
        let height = max(2, Int((abs(displayed.height) * scale / 2).rounded()) * 2)

        self.videoTrack = videoTrack
        self.audioTrack = audioTrack
        self.duration = duration
        durationMs = VideoTranscoder.milliseconds(duration)
        outputWidth = width
        outputHeight = height
        let sourceRate = nominalFrameRate > 0 ? Int(nominalFrameRate.rounded()) : VideoTranscoder.maxFramesPerSecond
        framesPerSecond = max(1, min(VideoTranscoder.maxFramesPerSecond, sourceRate))
        transform = preferredTransform
            .concatenating(CGAffineTransform(translationX: -displayed.minX, y: -displayed.minY))
            .concatenating(CGAffineTransform(scaleX: CGFloat(width) / abs(displayed.width),
                                             y: CGFloat(height) / abs(displayed.height)))
        audioChannels = try await Self.channelCount(audioTrack)
    }

    mutating func cut(to milliseconds: Int) {
        duration = CMTime(value: CMTimeValue(milliseconds), timescale: 1_000)
        durationMs = milliseconds
        isCut = true
    }

    private static func channelCount(_ track: AVAssetTrack?) async throws -> Int {
        guard let track else { return 0 }
        let descriptions = try await track.load(.formatDescriptions)
        let channels = descriptions.compactMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame
        }.first ?? 2
        return Int(min(max(channels, 1), 2))
    }

    func composition() -> AVVideoComposition {
        var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: videoTrack)
        layer.setTransform(transform, at: .zero)
        let instruction = AVVideoCompositionInstruction.Configuration(
            layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)],
            timeRange: CMTimeRange(start: .zero, duration: duration)
        )
        return AVVideoComposition(configuration: AVVideoComposition.Configuration(
            colorPrimaries: AVVideoColorPrimaries_ITU_R_709_2,
            colorTransferFunction: AVVideoTransferFunction_ITU_R_709_2,
            colorYCbCrMatrix: AVVideoYCbCrMatrix_ITU_R_709_2,
            frameDuration: CMTime(value: 1, timescale: CMTimeScale(framesPerSecond)),
            instructions: [AVVideoCompositionInstruction(configuration: instruction)],
            renderSize: CGSize(width: outputWidth, height: outputHeight)
        ))
    }

    func videoSettings() -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: outputWidth,
            AVVideoHeightKey: outputHeight,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: VideoTranscoder.videoBitsPerSecond,
                AVVideoExpectedSourceFrameRateKey: framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: framesPerSecond * 2,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String,
            ],
        ]
    }

    func pcmSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: VideoTranscoder.audioSampleRate,
            AVNumberOfChannelsKey: audioChannels,
            AVChannelLayoutKey: channelLayout(),
        ]
    }

    func aacSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: VideoTranscoder.audioSampleRate,
            AVNumberOfChannelsKey: audioChannels,
            AVEncoderBitRateKey: VideoTranscoder.audioBitsPerSecond,
            AVChannelLayoutKey: channelLayout(),
        ]
    }

    private func channelLayout() -> Data {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = audioChannels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }
}
