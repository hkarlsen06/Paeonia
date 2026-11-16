import AVKit
import Photos
import SwiftUI

/// A video to play full screen. `loadFile` returns a local file, such as the sender's own
/// copy or `VideoFileCache.fileURL(for:)`. Save calls it again, because the file it
/// returned may be gone by then.
struct PaeoniaVideoViewerItem: Identifiable {
    let id: String
    let loadFile: @Sendable () async throws -> PaeoniaVideoFile
}

struct PaeoniaVideoFile: Sendable {
    let url: URL
    /// The uploaded video the file may come from in `VideoFileCache`. A file that stops
    /// playing partway leaves the cache, so Try again downloads it anew.
    var mediaAssetID: UUID?
}

extension View {
    func paeoniaVideoViewer(item: Binding<PaeoniaVideoViewerItem?>) -> some View {
        fullScreenCover(item: item) { viewerItem in
            PaeoniaVideoViewer(item: viewerItem) { item.wrappedValue = nil }
        }
    }
}

/// Plays one video with sound, with Save to Photos. The only other place a player lives
/// is the story viewer. Lists show posters.
struct PaeoniaVideoViewer: View {
    let item: PaeoniaVideoViewerItem
    let onDismiss: () -> Void

    private enum Load {
        case loading
        case loaded(AVPlayer)
        case failed(PaeoniaFailure)
    }

    @Environment(\.openURL) private var openURL
    @State private var load = Load.loading
    @State private var loadAttempt = 0
    @State private var isSaving = false
    @State private var isSaved = false
    @State private var isShowingSavePermissionAlert = false
    @State private var bannerCenter = PaeoniaBannerCenter()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, PaeoniaSpacing.space20)
                    .padding(.top, PaeoniaSpacing.space20)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityAction(.escape) { onDismiss() }
        .statusBarHidden()
        .paeoniaBanner(bannerCenter)
        .task(id: loadAttempt) { await loadVideo() }
        .onDisappear(perform: stopPlayback)
        .alert(Text(.imageViewerSavePermissionTitle), isPresented: $isShowingSavePermissionAlert) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text(.commonOpenSettings)
            }
            Button(role: .cancel) {} label: {
                Text(.commonCancel)
            }
        } message: {
            Text(.videoViewerSavePermissionMessage)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch load {
        case .loading:
            ProgressView()
                .tint(.white.opacity(0.8))
                .accessibilityLabel(Text(.videoViewerLoading))
        case let .loaded(player):
            PaeoniaPlayerView(player: player)
                .accessibilityIdentifier("videoViewer.player")
        case let .failed(failure):
            ScrollView {
                PaeoniaLoadFailureView(
                    failure: failure,
                    offlineMessage: .videoViewerLoadOffline,
                    failedMessage: .videoViewerLoadFailed
                ) {
                    Button(.commonTryAgain) { loadAttempt += 1 }
                        .buttonStyle(PaeoniaPrimaryButtonStyle())
                        .accessibilityIdentifier("videoViewer.retry")
                }
                .padding(PaeoniaSpacing.space16)
                .paeoniaReadableWidth()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var topBar: some View {
        HStack {
            if case .loaded = load {
                PaeoniaViewerSaveButton(
                    isSaving: isSaving,
                    isSaved: isSaved,
                    accessibilityIdentifier: "videoViewer.save"
                ) {
                    Task { await save() }
                }
            }
            Spacer()
            PaeoniaViewerCloseButton(accessibilityIdentifier: "videoViewer.close", action: onDismiss)
        }
        .padding(.vertical, PaeoniaSpacing.space4)
    }

    private func loadVideo() async {
        if case .loaded = load { return }
        load = .loading
        do {
            let file = try await item.loadFile()
            guard !Task.isCancelled else { return }
            let player = AVPlayer(url: file.url)
            await DailyVoiceAudioSession.configureForVideoPlayback()
            // The viewer closed while the session was set up, after `stopPlayback` let go of it.
            guard !Task.isCancelled else {
                DailyVoiceAudioSession.deactivate()
                return
            }
            load = .loaded(player)
            player.play()
            if let playerItem = player.currentItem { await Self.untilFailed(playerItem) }
            guard !Task.isCancelled else { return }
            // A file that stops decoding partway shows the same failure as one that did not load.
            stopPlayback()
            if let mediaAssetID = file.mediaAssetID {
                await VideoFileCache.shared?.evict(mediaAssetIDs: [mediaAssetID])
            }
            load = .failed(.other)
        } catch {
            guard !Task.isCancelled else { return }
            load = .failed(PaeoniaFailure(error))
        }
    }

    /// Returns once `item` can't play on, or when the task is cancelled.
    private static func untilFailed(_ item: AVPlayerItem) async {
        let (failures, continuation) = AsyncStream<Void>.makeStream()
        let status = item.observe(\.status, options: [.initial, .new]) { item, _ in
            if item.status == .failed { continuation.yield() }
        }
        let failedToEnd = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: nil
        ) { _ in
            continuation.yield()
        }
        defer {
            status.invalidate()
            NotificationCenter.default.removeObserver(failedToEnd)
        }
        for await _ in failures { return }
    }

    /// Lets the person's music come back once the viewer closes.
    private func stopPlayback() {
        if case let .loaded(player) = load {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        DailyVoiceAudioSession.deactivate()
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let fileURL = try? await item.loadFile().url else {
            bannerCenter.show(.error(message: String(localized: .videoViewerSaveFailed)))
            return
        }
        switch await PhotoLibrarySaver().saveVideo(fileURL: fileURL) {
        case .saved:
            isSaved = true
            bannerCenter.show(
                .info(message: String(localized: .imageViewerSaved), systemImage: "square.and.arrow.down")
            )
        case .permissionDenied:
            switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
            case .denied:
                isShowingSavePermissionAlert = true
            case .restricted:
                bannerCenter.show(.error(message: String(localized: .videoViewerSaveRestricted)))
            default:
                bannerCenter.show(.error(message: String(localized: .videoViewerSaveFailed)))
            }
        case .failed:
            bannerCenter.show(.error(message: String(localized: .videoViewerSaveFailed)))
        }
    }
}

private struct PaeoniaPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        // The lock screen's Now Playing would otherwise show the couple's private video.
        controller.updatesNowPlayingInfoCenter = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}
