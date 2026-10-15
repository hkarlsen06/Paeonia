import CoreGraphics
import RealityKit

/// The person's hands on the camera: a one-finger drag orbits the board, a pinch
/// zooms toward the fingers, and a double tap glides back to the default view. The
/// camera orbits the board point in the middle of the view, so the board stays
/// where the person leaves it.
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

    // MARK: Orbit

    /// A finger went down and started to drag. It stops a glide or a slowing orbit.
    func beginOrbit() {
        glide = nil
        yawVelocity = 0
        pitchVelocity = 0
    }

    /// The finger moved by this many points. Dragging right turns the board to the
    /// right, and dragging down tips it toward a view from above.
    func orbit(byX dx: Double, y dy: Double) {
        pose.yaw -= dx * LudoSceneStyle.orbitYawPerPoint
        pose.pitch += dy * LudoSceneStyle.orbitPitchPerPoint
        pose = pose.clamped
        cameraNeedsUpdate = true
    }

    /// The finger lifted at this speed in points a second. The orbit keeps going and slows down.
    func endOrbit(velocityX: Double, velocityY: Double) {
        guard !reduceMotion else {
            notifyCameraSettled()
            return
        }
        yawVelocity = -velocityX * LudoSceneStyle.orbitYawPerPoint
        pitchVelocity = velocityY * LudoSceneStyle.orbitPitchPerPoint
        if abs(yawVelocity) < 0.05, abs(pitchVelocity) < 0.05 {
            yawVelocity = 0
            pitchVelocity = 0
            notifyCameraSettled()
        }
    }

    // MARK: Zoom

    /// Two fingers went down at `point`, from 0 to 1 across and down the view. The
    /// board point under them stays under them for the whole pinch.
    func beginZoom(at point: CGPoint) {
        glide = nil
        yawVelocity = 0
        pitchVelocity = 0
        zoomStart = pose.zoom
        zoomAnchor = rig?.boardPoint(at: point)
    }

    /// A pinch of `scale` times the start, with the fingers' middle now at `point`.
    /// Spreading the fingers moves the camera closer, and moving them slides the board along.
    func zoom(scale: Double, at point: CGPoint) {
        guard let start = zoomStart, let fit, scale > 0 else { return }
        if let anchor = zoomAnchor {
            pose = fit.pose(pose, zoom: start / scale, keeping: anchor, at: point)
        } else {
            pose.zoom = start / scale
            pose = pose.clamped
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
        yawVelocity = 0
        pitchVelocity = 0
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

    /// Runs the glide or the slowing orbit for one frame, then moves the camera.
    func updateCamera(deltaTime: Double) {
        if let glide {
            let amount = LudoMotion.smooth((clock - glide.start) / LudoSceneStyle.cameraResetDuration)
            pose = glide.from.blended(to: .home, amount: amount)
            cameraNeedsUpdate = true
            if amount >= 1 {
                self.glide = nil
                pose = .home
                notifyCameraSettled()
            }
        } else if yawVelocity != 0 || pitchVelocity != 0 {
            let before = pose.pitch
            pose.yaw += yawVelocity * deltaTime
            pose.pitch += pitchVelocity * deltaTime
            pose = pose.clamped
            if pose.pitch != before + pitchVelocity * deltaTime { pitchVelocity = 0 }
            let slowing = exp(-LudoSceneStyle.orbitFriction * deltaTime)
            yawVelocity *= slowing
            pitchVelocity *= slowing
            cameraNeedsUpdate = true
            if abs(yawVelocity) < 0.03, abs(pitchVelocity) < 0.03 {
                yawVelocity = 0
                pitchVelocity = 0
                notifyCameraSettled()
            }
        }
        applyCamera()
    }

    private func notifyCameraSettled() {
        if let rig { onCameraSettled?(rig) }
    }
}
