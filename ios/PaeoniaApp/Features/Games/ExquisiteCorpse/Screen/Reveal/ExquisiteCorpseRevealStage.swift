import SwiftUI

/// The part of the reveal that moves: the figure under the camera, the light and
/// the petals behind it, the caption of the part that plays, and the "Opening…"
/// label while the drawings load. It is one VoiceOver element.
struct ExquisiteCorpseRevealStage: View {
    let content: ExquisiteCorpseRevealContent
    let timeline: ExquisiteCorpseRevealTimeline
    let player: ExquisiteCorpseFigurePlayer
    let camera: ExquisiteCorpseRevealCamera
    /// When the petals started flying. Nil when they are not.
    let bloomStart: Date?
    let reduceMotion: Bool
    /// "Show the whole figure" has something to do.
    let canShowAll: Bool
    let onShowAll: () -> Void
    let onPlayAgain: () -> Void

    var body: some View {
        let size = camera.stage
        let figureCenter = CGPoint(x: size.width / 2, y: camera.overviewHeight / 2)
        let bloomSide = max(size.width, size.height)
        ZStack {
            ExquisiteCorpseRevealGlow(
                level: glowLevel,
                pulse: timeline.showsBloom,
                center: figureCenter,
                fitSide: camera.fitSide,
                reach: max(size.width, camera.overviewHeight) * 0.6
            )
            if let bloomStart {
                // Placed, not centered, so the petals leave from the middle of the
                // figure and the wide canvas never widens the stage under the glow.
                GamePetalBloom(start: bloomStart, seed: content.figureID.uuidString)
                    .frame(width: bloomSide, height: bloomSide)
                    .position(figureCenter)
            }
            ExquisiteCorpseRevealFigure(
                player: player,
                camera: camera,
                shot: shot,
                openParts: timeline.openParts,
                isLoaded: content.isReady,
                isWaiting: !content.isReady,
                reduceMotion: reduceMotion,
                cameraAnimation: cameraAnimation
            )
            loadingLabel
            caption
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(figureLabel)
        .accessibilityAddTraits(.isImage)
        .accessibilityActions {
            if canShowAll {
                Button { onShowAll() } label: { Text(.exquisiteCorpseRevealShowAll) }
            }
            if timeline.isSettled {
                Button { onPlayAgain() } label: { Text(.exquisiteCorpseRevealReplay) }
            }
        }
        .accessibilityIdentifier("corpse.reveal.figure")
    }

    // MARK: Layers

    /// "Opening…" on the middle fold while the drawings download.
    private var loadingLabel: some View {
        ZStack {
            if !content.isReady {
                Text(.exquisiteCorpseRevealLoading)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: max(camera.fitSide - PaeoniaSpacing.space16, 0))
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: content.isReady)
        .allowsHitTesting(false)
    }

    /// Who drew the part that plays, under its square.
    private var caption: some View {
        ZStack {
            if let part = captionPart {
                ExquisiteCorpseRevealCaption(part: part)
                    .id(part.kind)
                    .transition(Self.captionTransition)
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.meaningfulMoment, value: captionPart?.kind)
        .frame(maxWidth: .infinity)
        .frame(height: camera.captionZone)
        .offset(y: camera.captionTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    /// The caption of the part before leaves quickly, and the next one comes in
    /// after it, so two names never show on top of each other. Both are done as
    /// the fold finishes opening.
    private static let captionTransition = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 6))
            .animation(PaeoniaMotion.stateChange.delay(PaeoniaMotion.motionFast)),
        removal: .opacity.animation(PaeoniaMotion.buttonPress)
    )

    // MARK: Derived state

    private var shot: ExquisiteCorpseRevealCamera.Shot {
        switch timeline.stage {
        case let .opening(part), let .playing(part): .framing(part)
        case .folded, .zoomingOut, .settled: .overview
        }
    }

    private var cameraAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return timeline.stage == .zoomingOut ? PaeoniaMotion.celebrationReveal : PaeoniaMotion.meaningfulMoment
    }

    private var captionPart: ExquisiteCorpseRevealContent.Part? {
        switch timeline.stage {
        case let .opening(part), let .playing(part): content.part(part)
        case .folded, .zoomingOut, .settled: nil
        }
    }

    private var glowLevel: Double {
        guard !reduceMotion else { return 0 }
        return timeline.showsBloom || timeline.isSettled ? ExquisiteCorpseRevealGlow.restingLevel : 0
    }

    private var figureLabel: Text {
        content.isReady
            ? Text(.exquisiteCorpseRevealFigureA11Y(content.number, content.partnerName))
            : Text(.exquisiteCorpseRevealLoading)
    }
}
