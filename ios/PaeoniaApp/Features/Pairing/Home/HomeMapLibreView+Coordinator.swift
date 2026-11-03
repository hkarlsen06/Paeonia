import MapLibre
import UIKit

extension HomeMapLibreView {
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: HomeMapLibreView?
        var lastFraming: FramingKey?
        /// MapLibre drops timed camera moves until the map has loaded.
        var isLoaded = false
        private var didFail = false
        private var loadTask: Task<Void, Never>?
        weak var map: MLNMapView?
        var intro = Intro.none
        /// From 0 to 1 as the intro carries the avatars to their places. 1 without an intro.
        var introProgress: Double = 1
        /// Both places on the intro's first camera. They miss the waiting avatars when the
        /// map can't zoom out far enough.
        var introStartPoints = HomeMapAvatarPoints(own: .zero, partner: .zero)
        private var projectionTask: Task<Void, Never>?

        /// Frames the map again when the couple, the box or the view's real size changed.
        /// The box must fit inside the view, or the fit has no room and zooms out to the world.
        func frameIfNeeded(_ map: MLNMapView) {
            guard let parent, map.bounds.width > 0, map.bounds.height >= parent.framedBox.maxY,
                  parent.explorer?.isExploring != true else { return }
            let key = framingKey(parent, map)
            guard key != lastFraming else { return }
            // A new place or box after the first framing moves the map. A new size jumps,
            // since the old view's camera doesn't fit it.
            let animated = lastFraming?.size == key.size && isLoaded && !UIAccessibility.isReduceMotionEnabled
            let isFirstFraming = lastFraming == nil
            lastFraming = key
            self.map = map
            guard !holdsIntro(map, isFirstFraming: isFirstFraming) else { return }
            parent.frame(map, animated: animated) { [weak self] in self?.lastFraming == key }
            handOverToExplorer(map)
        }

        /// Lets the person move the map, and moves it back to the couple when they ask.
        func handOverToExplorer(_ map: MLNMapView) {
            guard let explorer = parent?.explorer, explorer.map !== map else { return }
            explorer.attach(map) { [weak self, weak map] in
                guard let self, let map, let parent = self.parent else { return }
                let key = self.framingKey(parent, map)
                self.lastFraming = key
                parent.frame(map, animated: self.isLoaded && !UIAccessibility.isReduceMotionEnabled) { [weak self] in
                    self?.lastFraming == key
                }
            }
        }

        private func framingKey(_ parent: HomeMapLibreView, _ map: MLNMapView) -> FramingKey {
            FramingKey(
                current: parent.current, partner: parent.partner, box: parent.framedBox,
                size: map.bounds.size, avatarSize: parent.avatarSize
            )
        }

        // Give SwiftUI time to lay out before the map draws. The render callback
        // also covers the first frame and changes made without animation.
        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            publishProjection(mapView)
        }

        func mapViewWillStartRenderingFrame(_ mapView: MLNMapView) {
            publishProjection(mapView)
        }

        private func publishProjection(_ mapView: MLNMapView) {
            // Camera setters can call the delegate while updateUIView is running.
            // Publish the latest projection after that update, once per run-loop turn.
            guard projectionTask == nil else { return }
            projectionTask = Task { @MainActor [weak self, weak mapView] in
                await Task.yield()
                guard let self else { return }
                self.projectionTask = nil
                guard let mapView else { return }
                self.publishCurrentProjection(mapView)
            }
        }

        private func publishCurrentProjection(_ mapView: MLNMapView) {
            guard let parent, lastFraming != nil else { return }
            parent.onProjection(HomeMapProjection(
                own: mapView.convert(parent.current, toPointTo: mapView),
                partner: mapView.convert(parent.partner, toPointTo: mapView),
                direction: mapView.direction,
                zoom: mapView.zoomLevel,
                introProgress: introProgress,
                introStart: introStartPoints
            ))
        }

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            loadTask?.cancel()
            isLoaded = true
            didFail = false
            parent?.tiles.mapLoaded()
            startIntroIfReady()
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: any Error) {
            isLoaded = false
            didFail = true
            guard let tiles = parent?.tiles else { return }
            loadTask?.cancel()
            loadTask = Task { await tiles.mapDidNotLoad() }
        }

        /// A map that has not drawn within `HomeMapTileStatus.loadTimeout` of active app time
        /// counts as failed. MapLibre draws nothing while the app is inactive, as when iOS
        /// launches it behind the lock screen, so the wait starts over once the app is active.
        func watchLoad() {
            loadTask?.cancel()
            loadTask = nil
            guard UIApplication.shared.applicationState == .active else { return }
            loadTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: HomeMapTileStatus.loadTimeout)
                } catch {
                    return
                }
                guard let self, !self.isLoaded, let tiles = self.parent?.tiles else { return }
                self.didFail = true
                await tiles.mapDidNotLoad()
            }
        }

        override init() {
            super.init()
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(appDidBecomeActive),
                               name: UIApplication.didBecomeActiveNotification, object: nil)
            center.addObserver(self, selector: #selector(appWillResignActive),
                               name: UIApplication.willResignActiveNotification, object: nil)
        }

        /// The map is still loading and no check of OpenFreeMap has started.
        private var isWaitingForLoad: Bool { parent != nil && !isLoaded && !didFail }

        @objc private func appDidBecomeActive() {
            guard isWaitingForLoad else { return }
            watchLoad()
        }

        @objc private func appWillResignActive() {
            guard isWaitingForLoad else { return }
            loadTask?.cancel()
            loadTask = nil
        }

        func stopWatchingLoad() {
            loadTask?.cancel()
            loadTask = nil
            parent = nil
        }

        /// MapLibre gives up on a style that failed to load. Once a check finds OpenFreeMap
        /// answering again, the map asks for it once more.
        func reloadIfTilesReturned(_ map: MLNMapView) {
            guard didFail, !isLoaded, parent?.tiles.tiles == .available else { return }
            didFail = false
            watchLoad()
            map.reloadStyle(nil)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            HomeMapLibreView.recolor(style)
        }
    }
}

/// The positions on the camera being drawn, before any avatar spacing is applied.
struct HomeMapProjection: Equatable {
    let own: CGPoint
    let partner: CGPoint
    let direction: Double
    let zoom: Double
    /// From 0 to 1 while the intro plays (`HomeMapLibreView+Intro`), 1 after.
    let introProgress: Double
    /// The positions on the intro's first camera.
    let introStart: HomeMapAvatarPoints
}
