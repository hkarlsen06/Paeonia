import CoreGraphics
import RealityKit

/// The person's hands on the camera: a pinch zooms toward the fingers and slides the
/// board along, a twist of the two fingers turns it, and a double tap glides back to
/// the default view. One finger never moves the camera, because one finger throws
/// the die and picks pawns.
extension LudoStage {
    /// Fits the camera to a view of this shape, keeping the board and the props inside
    /// `fitHeight` of the view's height.
    func setAspect(_ aspect: Double, fitHeight: Double) {
        let next = LudoCameraFit.make(aspect: aspect, fitHeight: fitHeight)
        if let fit, abs(next.aspect - fit.aspect) < 0.001,
           abs(next.fitHeight - fit.fitHeight) < 0.001 { return }
        fit = next
        cameraNeedsUpdate = true
        applyCamera()
        notifyCameraSettled()
    }

    /// Moves the camera entity when the pose or the fit changed.
    func applyCamera() {
        guard cameraNeedsUpdate, let rig else { return }
        cameraNeedsUpdate = false
        camera.look(at: rig.target, from: rig.position, relativeTo: nil)
    }

    // MARK: Zoom

    /// Two fingers went down at `point`, from 0 to 1 across and down the view. The
    /// board point under them stays under them for the whole pinch and twist.
    func beginZoom(at point: CGPoint) {
        glide = nil
        zoomStart = pose
        zoomAnchor = rig?.boardPoint(at: point)
    }

    /// A pinch of `scale` times the start and a twist of `twist` radians clockwise,
    /// with the fingers' middle now at `point`. Spreading the fingers moves the camera
    /// closer, twisting them turns the board the same way, and moving them slides the
    /// board along. A twist smaller than `twistDeadZone` does nothing, so a pinch does
    /// not wobble the board.
    func zoom(scale: Double, twist: Double, at point: CGPoint) {
        guard let start = zoomStart, let fit, scale > 0 else { return }
        var turned = pose
        let turn = max(abs(twist) - LudoSceneStyle.twistDeadZone, 0)
        turned.yaw = start.yaw + (twist < 0 ? -turn : turn)
        if let anchor = zoomAnchor {
            pose = fit.pose(turned, zoom: start.zoom / scale, keeping: anchor, at: point)
        } else {
            turned.zoom = start.zoom / scale
            pose = turned.clamped
        }
        cameraNeedsUpdate = true
    }

    func endZoom() {
        zoomStart = nil
        zoomAnchor = nil
        notifyCameraSettled()
    }

    // MARK: Reset

    /// Back to the default view. Reduce Motion cuts instead of gliding.
    func resetCamera() {
        zoomStart = nil
        zoomAnchor = nil
        guard !reduceMotion, pose != .home else {
            pose = .home
            cameraNeedsUpdate = true
            glide = nil
            applyCamera()
            notifyCameraSettled()
            return
        }
        glide = CameraGlide(from: pose, start: clock)
    }

    // MARK: Frames

    /// Runs the glide for one frame, then moves the camera.
    func updateCamera() {
        if let glide {
            let amount = LudoMotion.smooth((clock - glide.start) / LudoSceneStyle.cameraResetDuration)
            pose = glide.from.blended(to: .home, amount: amount)
            cameraNeedsUpdate = true
            if amount >= 1 {
                self.glide = nil
                pose = .home
                notifyCameraSettled()
            }
        }
        applyCamera()
    }

    private func notifyCameraSettled() {
        if let rig { onCameraSettled?(rig) }
    }
}
