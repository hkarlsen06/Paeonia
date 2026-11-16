import AVFoundation
import Observation
import SwiftUI
import UIKit

/// The story viewer's one video player. The viewer owns it for as long as it is open
/// and loads each video story into it, so moving between stories never makes a new
/// player. It plays in the app's resting `.ambient` audio session, so the person's music
/// keeps playing and the silent switch mutes the story. During a call it stays silent.
@Observable
final class StoryVideoPlayback {
    enum Phase: Equatable {
        case idle
        case loading(UUID)
        /// The first frame can show.
        case ready(UUID)
        case failed(UUID)
    }

    let player = AVPlayer()
    private(set) var phase = Phase.idle
    /// The current video played to its end.
    private(set) var hasEnded = false

    @ObservationIgnored private var wantsPlaying = false
    @ObservationIgnored private var itemObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init() {
        player.actionAtItemEnd = .pause
        player.allowsExternalPlayback = false
    }

    func isReady(_ mediaAssetID: UUID) -> Bool {
        phase == .ready(mediaAssetID)
    }

    func hasFailed(_ mediaAssetID: UUID) -> Bool {
        phase == .failed(mediaAssetID)
    }

    /// How far the video has played, from 0 to 1.
    var progress: Double {
        guard let item = player.currentItem else { return 0 }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(item.currentTime().seconds / duration, 0), 1)
    }

    /// Loads a story's video from `VideoFileCache`, paused at the start. A newer load or
    /// `stop()` cancels this one, so a skipped story stops downloading.
    func load(_ mediaAssetID: UUID) {
        if phase == .ready(mediaAssetID) || phase == .loading(mediaAssetID) { return }
        // The viewer says when to play, once the first frame shows.
        wantsPlaying = false
        clearItem()
        phase = .loading(mediaAssetID)
        loadTask = Task { await prepare(mediaAssetID) }
    }

    private func prepare(_ mediaAssetID: UUID) async {
        let item: AVPlayerItem
        do {
            guard let cache = VideoFileCache.shared else { throw VideoFileCacheError.unavailable }
            // A damaged file leaves the cache, so Try again downloads it anew.
            item = AVPlayerItem(url: try await cache.fileURL(for: mediaAssetID, priority: .playback))
        } catch {
            if !Task.isCancelled { phase = .failed(mediaAssetID) }
            return
        }
        guard !Task.isCancelled else { return }
        player.replaceCurrentItem(with: item)
        observe(item, of: mediaAssetID)
        // A file that opens can still fail once the player prepares it.
        let status = await Self.preparedStatus(of: item)
        // Navigation may have stopped this load or started another while the player prepared it.
        guard !Task.isCancelled, phase == .loading(mediaAssetID), player.currentItem === item else { return }
        switch status {
        case .readyToPlay:
            phase = .ready(mediaAssetID)
            applyPlaying()
        case .failed:
            await failPlaying(item, mediaAssetID)
        default:
            break
        }
    }

    private func observe(_ item: AVPlayerItem, of mediaAssetID: UUID) {
        itemObservers = [
            NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.hasEnded = true }
            },
            // A file that stops decoding partway shows the retry button, like one that
            // did not load.
            NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak self, weak item] _ in
                MainActor.assumeIsolated {
                    guard let self, let item else { return }
                    Task { await self.failPlaying(item, mediaAssetID) }
                }
            }
        ]
    }

    /// The item's status once the player has prepared it, or `.unknown` when the load is cancelled.
    private nonisolated static func preparedStatus(of item: AVPlayerItem) async -> AVPlayerItem.Status {
        let (statuses, continuation) = AsyncStream<AVPlayerItem.Status>.makeStream()
        let observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            if item.status != .unknown { continuation.yield(item.status) }
        }
        defer { observation.invalidate() }
        for await status in statuses { return status }
        return .unknown
    }

    /// Plays or pauses. A video that has not loaded yet starts once it is ready.
    func setPlaying(_ playing: Bool) {
        wantsPlaying = playing
        applyPlaying()
    }

    /// Back to the first frame, playing if it was meant to be.
    func restart() {
        hasEnded = false
        player.seek(to: .zero)
        applyPlaying()
    }

    func stop() {
        wantsPlaying = false
        clearItem()
        phase = .idle
    }

    /// The file did not play. It leaves the cache before Try again shows, so the retry
    /// downloads it anew.
    private func failPlaying(_ item: AVPlayerItem, _ mediaAssetID: UUID) async {
        guard player.currentItem === item else { return }
        await VideoFileCache.shared?.evict(mediaAssetIDs: [mediaAssetID])
        guard player.currentItem === item else { return }
        clearItem()
        phase = .failed(mediaAssetID)
    }

    private func applyPlaying() {
        guard wantsPlaying, case .ready = phase, !hasEnded else {
            player.pause()
            return
        }
        player.isMuted = PaeoniaAudioSession.isCallActive
        PaeoniaAudioSession.useAmbient()
        player.play()
    }

    private func clearItem() {
        loadTask?.cancel()
        player.pause()
        for observer in itemObservers { NotificationCenter.default.removeObserver(observer) }
        itemObservers = []
        hasEnded = false
        player.replaceCurrentItem(with: nil)
    }
}

/// A video story fitted to the screen, or the loading state until its first frame can
/// show. A failed video retries on tap.
struct StoryVideoView: View {
    let playback: StoryVideoPlayback
    let mediaAssetID: UUID
    /// Called once the first frame can show, so the viewer only starts then.
    var onLoaded: () -> Void = {}

    var body: some View {
        ZStack {
            if playback.isReady(mediaAssetID) {
                StoryPlayerLayerView(player: playback.player, videoGravity: .resizeAspect)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .onAppear(perform: onLoaded)
            } else if playback.hasFailed(mediaAssetID) {
                Button {
                    playback.load(mediaAssetID)
                } label: {
                    VStack(spacing: PaeoniaSpacing.space8) {
                        Image(systemName: "video")
                            .font(.largeTitle)
                            .accessibilityHidden(true)
                        Text(.storiesViewerVideoFailed)
                            .font(PaeoniaTypography.caption)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            } else {
                ProgressView()
                    .tint(.white)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shows a player's picture. The player belongs to a model, never to this view.
struct StoryPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity

    func makeUIView(context _: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ view: PlayerView, context _: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        view.playerLayer.videoGravity = videoGravity
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer {
            // swiftlint:disable:next force_cast
            layer as! AVPlayerLayer
        }
    }
}
