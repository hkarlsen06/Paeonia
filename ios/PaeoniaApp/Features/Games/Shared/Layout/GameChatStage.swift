import SwiftUI
import UIKit

/// The frame, in its game screen, of the part worth watching while the game's chat is open,
/// such as the board or the drawing.
struct GameChatStageKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    /// Two phases of a game overlap while one fades out. The later one is the new phase.
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

extension EnvironmentValues {
    /// The room above the game chat panel while it is open, from the status bar down to
    /// the panel, in global coordinates.
    @Entry var gameChatStageRoom: CGRect?
    /// How far the game screen is shrunk for its chat panel. 1 is full size.
    @Entry var gameChatStageScale: CGFloat = 1
}

extension View {
    /// Marks the part of a game screen that stays on screen above its chat panel.
    func gameChatStage() -> some View {
        background {
            GeometryReader { proxy in
                // Whole points, so a scroll view that settles by fractions of a point does
                // not move the stage.
                let frame = proxy.frame(in: .named(GameChatStageZoom.space))
                let stage = CGRect(
                    x: frame.minX.rounded(), y: frame.minY.rounded(),
                    width: frame.width.rounded(), height: frame.height.rounded())
                Color.clear.preference(key: GameChatStageKey.self, value: stage)
            }
        }
    }

    /// Shrinks a game screen to its stage while the game's chat panel is open.
    func gameChatStageZoom() -> some View {
        modifier(GameChatStageZoom())
    }
}

/// While the game's chat panel is open (`GameChatPanel`), shrinks a game screen until its
/// stage (`gameChatStage`) fits in the room above the panel, and covers the rest of the
/// screen. A screen that marks no stage stays as it is.
///
/// It scales the screen from inside its navigation destination. A scale around the whole
/// navigation stack moves the stack's view, and UIKit then gives the screen a larger top
/// safe area, which pushes the stage down. The navigation bar is outside the destination,
/// so it fades out instead (`GameNavigationBarFade`).
struct GameChatStageZoom: ViewModifier {
    static let space = "gameChatStage"
    private static let padding = PaeoniaSpacing.space8

    @Environment(\.gameChatStageRoom) private var room
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The screen's frame in global coordinates, and the stage's frame in the screen.
    @State private var frame = CGRect.zero
    @State private var stage: CGRect?
    /// The keyboard on screen is the chat's. It stays so until it is gone, which is
    /// after the panel has closed.
    @State private var chatHasKeyboard = false

    func body(content: Content) -> some View {
        let zoom = zoom
        let keyboardIsChats = room != nil || chatHasKeyboard
        let animation = reduceMotion ? nil : Animation.spring(duration: PaeoniaMotion.motionMorph, bounce: 0)
        content
            .environment(\.gameChatStageScale, zoom?.scale ?? 1)
            .environment(\.keyboardBelongsElsewhere, keyboardIsChats)
            .coordinateSpace(.named(Self.space))
            .onPreferenceChange(GameChatStageKey.self) { stage = $0 }
            .overlay {
                StageCutout(
                    stage: zoom?.stage ?? CGRect(origin: .zero, size: frame.size), radius: PaeoniaRadius.standard
                )
                .fill(.paeoniaBackgroundSecondary, style: FillStyle(eoFill: true))
                .opacity(zoom == nil ? 0 : 1)
                .animation(animation, value: zoom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .modifier(GameChatTransform(scale: zoom?.scale ?? 1, offset: zoom?.offset ?? .zero))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            // The bar's buttons would sit over the stage.
            .background { GameNavigationBarFade(isFaded: zoom != nil) }
            // The chat's keyboard would squeeze the game above the panel, and again on its way out.
            .ignoresSafeArea(.keyboard, edges: keyboardIsChats ? .bottom : [])
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                if room != nil { chatHasKeyboard = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                chatHasKeyboard = false
            }
            .animation(animation, value: zoom)
    }

    private var zoom: Zoom? {
        guard let stage, stage.width > 0, stage.height > 0,
            let room = room?.offsetBy(dx: -frame.minX, dy: -frame.minY).insetBy(dx: Self.padding, dy: Self.padding),
            room.width > 0, room.height > 0
        else { return nil }
        let scale = min(room.width / stage.width, room.height / stage.height, 1)
        return Zoom(
            stage: stage,
            scale: scale,
            offset: CGSize(width: room.midX - scale * stage.midX, height: room.midY - scale * stage.midY)
        )
    }

    private struct Zoom: Equatable {
        let stage: CGRect
        let scale: CGFloat
        let offset: CGSize
    }
}

/// Fades the navigation bar of a game screen out and back in. Hiding the bar would give
/// the screen the bar's height, and the game would lay itself out again as it shrinks.
private struct GameNavigationBarFade: UIViewRepresentable {
    let isFaded: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let isFaded = isFaded
        let duration = context.environment.accessibilityReduceMotion ? 0 : PaeoniaMotion.motionDefault
        // The navigation controller is found once the view is in a window.
        DispatchQueue.main.async {
            context.coordinator.fade(isFaded, from: uiView, duration: duration)
        }
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.restore()
    }

    @MainActor
    final class Coordinator {
        /// Too faint to see. At 0 the screen gets the bar's height, as if the bar were hidden.
        private static let fadedAlpha: CGFloat = 0.01
        private weak var bar: UINavigationBar?

        func fade(_ isFaded: Bool, from view: UIView, duration: TimeInterval) {
            // A screen under another one is out of the window and leaves the bar to that one.
            guard view.window != nil else { return }
            let bar = bar ?? view.gameNavigationController()?.navigationBar
            self.bar = bar
            let alpha: CGFloat = isFaded ? Self.fadedAlpha : 1
            guard let bar, bar.alpha != alpha else { return }
            UIView.animate(withDuration: duration) { bar.alpha = alpha }
        }

        func restore() {
            bar?.alpha = 1
        }
    }
}

/// A scale around the top left corner and a move, as one transform. As a `scaleEffect` and
/// an `offset`, the offset of a view with UIKit views inside lands at once while the scale
/// animates. The game screen shrinks with it and the chat panel slides with it.
nonisolated struct GameChatTransform: GeometryEffect {
    var scale: CGFloat = 1
    var offset: CGSize

    var animatableData: AnimatablePair<CGFloat, CGSize.AnimatableData> {
        get { AnimatablePair(scale, offset.animatableData) }
        set {
            scale = newValue.first
            offset.animatableData = newValue.second
        }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offset.width, ty: offset.height))
    }
}

/// Everything around the stage, far past the screen's edges, so the cover still reaches
/// them after the screen shrinks.
private nonisolated struct StageCutout: Shape {
    var stage: CGRect
    let radius: CGFloat

    var animatableData: CGRect.AnimatableData {
        get { stage.animatableData }
        set { stage.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -4_000, dy: -4_000))
        path.addRoundedRect(in: stage, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return path
    }
}
