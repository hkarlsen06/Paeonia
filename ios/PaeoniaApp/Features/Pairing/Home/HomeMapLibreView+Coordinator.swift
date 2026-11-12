import MapLibre
import Observation
import OSLog
import UIKit

extension HomeMapLibreView {
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: HomeMapLibreView?
        var lastFraming: FramingKey?
        /// MapLibre drops timed camera moves until the map has loaded.
        var isLoaded = false
        private var didFail = false
        private(set) var loadTask: Task<Void, Never>?
        private var retryTask: Task<Void, Never>?
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
            // HomeMapBand already interpolates the box alongside the cards. Apply each
            // frame directly instead of restarting a camera animation on every layout tick.
            // A location update can also change the box when the couple becomes near.
            let locationsChanged = lastFraming.map {
                $0.current.latitude != key.current.latitude || $0.current.longitude != key.current.longitude
                    || $0.partner.latitude != key.partner.latitude || $0.partner.longitude != key.partner.longitude
            } ?? false
            let animated = lastFraming?.size == key.size && (lastFraming?.box == key.box || locationsChanged)
                && isLoaded && !UIAccessibility.isReduceMotionEnabled
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
            retryTask?.cancel()
            retryTask = nil
            isLoaded = true
            didFail = false
            parent?.tiles.mapLoaded()
            startIntroIfReady()
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: any Error) {
            let underlying = error as NSError
            HomeMapTileStatus.logger.error("""
                MapLibre load failed: domain=\(underlying.domain, privacy: .public) \
                code=\(underlying.code) detail=\(underlying.localizedDescription, privacy: .private)
                """)
            isLoaded = false
            didFail = true
            checkAfterLoadFailure(mapView)
        }

        private func checkAfterLoadFailure(_ mapView: MLNMapView) {
            guard UIApplication.shared.applicationState == .active, let tiles = parent?.tiles else { return }
            let previous = loadTask
            previous?.cancel()
            loadTask = Task { [weak self, weak mapView] in
                await previous?.value
                guard !Task.isCancelled else { return }
                await tiles.mapDidNotLoad()
                guard !Task.isCancelled, let self, let mapView else { return }
                self.reloadIfTilesReturned(mapView)
            }
        }

        /// Checks reachability after a loading delay, without interrupting the renderer.
        /// MapLibre pauses rendering while the app is inactive, so the timer restarts on return.
        func watchLoad() {
            let previous = loadTask
            previous?.cancel()
            guard UIApplication.shared.applicationState == .active else { return }
            loadTask = Task { [weak self] in
                await previous?.value
                guard !Task.isCancelled else { return }
                do {
                    try await Task.sleep(for: HomeMapTileStatus.loadTimeout)
                } catch {
                    return
                }
                guard let self, !self.isLoaded, let tiles = self.parent?.tiles else { return }
                HomeMapTileStatus.logger.notice("Map still loading after 10 active seconds; checking endpoints")
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
            if didFail, let map { checkAfterLoadFailure(map) }
            if isWaitingForLoad { watchLoad() }
        }

        @objc private func appWillResignActive() {
            retryTask?.cancel()
            retryTask = nil
            loadTask?.cancel()
        }

        func stopWatchingLoad() {
            loadTask?.cancel()
            loadTask = nil
            retryTask?.cancel()
            retryTask = nil
            parent = nil
        }

        /// MapLibre gives up on a style that failed to load. Once a check finds OpenFreeMap
        /// answering again, the map asks for it once more.
        func reloadIfTilesReturned(_ map: MLNMapView) {
            guard didFail, !isLoaded, parent?.tiles.tiles == .available,
                  UIApplication.shared.applicationState == .active, retryTask == nil else { return }
            // An actual style failure needs a reload. Space retries so a reachable but
            // invalid style cannot cause a reload loop.
            retryTask = Task { [weak self, weak map] in
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.retryTask = nil
                guard let map, self.didFail, !self.isLoaded,
                      self.parent?.tiles.tiles == .available,
                      UIApplication.shared.applicationState == .active else { return }
                HomeMapTileStatus.logger.notice("Retrying MapLibre style after a load error")
                self.didFail = false
                self.watchLoad()
                map.reloadStyle(nil)
            }
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            HomeMapTileStatus.logger.notice("MapLibre style loaded")
            HomeMapLibreView.recolor(style)
        }
    }
}

/// The projection the map last drew. A class, so a new one each frame updates only the
/// views that read it.
@Observable
final class HomeMapCamera {
    var projection: HomeMapProjection?
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
