import SwiftUI

/// The videos of the call screen (`CallStage`): one fills the stage, and the others are previews in
/// the person's corner (`CallPreviewCorner`). A tap on a preview makes it the big one, and the big one
/// takes the preview's place. A drag moves the previews together to any corner, as in FaceTime. Each
/// video keeps its one view through every swap, so a paused partner's last frame stays on screen.
struct CallStageView: View {
    let engine: any CallEngineActions
    let session: CallSession
    let stage: CallStage
    let partnerName: String
    /// Where the stage shows in the window: the whole screen, or the preview over the chat.
    let frame: CGRect
    /// The room the previews leave at the stage's edges, on screen, such as for the controls.
    let margins: EdgeInsets
    /// The screen's own edges inside `frame`, on screen. A shared screen stays inside them.
    let safeArea: EdgeInsets
    let turn: CallTurn
    /// Over the chat only the big video shows.
    let showsPreviews: Bool
    let cornerRadius: CGFloat
    @Binding var corner: CallPreviewCorner
    let bringForward: (CallVideoSource) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset = CGSize.zero

    static let space = "callStage"
    private static let previewRadius = PaeoniaRadius.radius20

    var body: some View {
        let layout = CallStageLayout(
            stage: stage, session: session, in: frame, margins: margins, safeArea: safeArea, corner: corner,
            turn: turn)
        ZStack {
            ForEach(stage.sources, id: \.self) { source in
                if let tile = layout.tiles[source] {
                    self.tile(source, at: tile, isMain: source == stage.main)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(.named(Self.space))
    }

    /// One structure for the big video and a preview, so a swap moves the same view instead of
    /// building a new one.
    private func tile(_ source: CallVideoSource, at tile: CallStageLayout.Tile, isMain: Bool) -> some View {
        let offset = isMain ? .zero : dragOffset
        let isShown = isMain || showsPreviews
        let swaps = isMain ? GestureMask.none : .all
        // A preview gets the button trait below. The big video takes no tap of its own.
        // swiftlint:disable:next accessibility_trait_for_button
        return CallStageTile(engine: engine, source: source, session: session, partnerName: partnerName)
            // The video view takes no touches, so the tile needs a shape of its own.
            .contentShape(.rect)
            // The big video leaves its taps to the call screen, which hides and shows the controls.
            .gesture(TapGesture().onEnded { bringForward(source) }, including: swaps)
            .gesture(drag, including: swaps)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(source.accessibilityLabel(partnerName: partnerName))
            .accessibilityValue(source == .partner
                ? CallPartnerVideoCover.accessibilityValue(of: session, partnerName: partnerName) : Text(verbatim: ""))
            .accessibilityAddTraits(isMain ? [] : .isButton)
            .accessibilityHint(isMain ? Text(verbatim: "") : Text(.callsPreviewHint))
            .accessibilityAction {
                if !isMain { bringForward(source) }
            }
            .accessibilityIdentifier(source.accessibilityIdentifier)
            .modifier(CallTilePlacement(
                center: CGPoint(x: tile.center.x + offset.width, y: tile.center.y + offset.height),
                size: tile.size, degrees: turn.angle.degrees,
                cornerRadius: isMain ? cornerRadius : Self.previewRadius, isOutlined: !isMain))
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
            .zIndex(isMain ? 0 : 1)
            // A scale here would grow the whole stage around its middle, so a tile only fades.
            .transition(.opacity)
    }

    /// Moves every preview together, so they never cover each other, and settles them in the corner
    /// the throw heads for. Takes the drag from the call screen's swipe down.
    private var drag: some Gesture {
        DragGesture(coordinateSpace: .named(Self.space))
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.15)) {
                    corner = CallStageLayout.corner(nearest: value.predictedEndLocation, in: frame, turn: turn)
                    dragOffset = .zero
                }
            }
    }
}

/// One video with what it says when the partner's picture stops: blurred with a spinner while it
/// catches up, or with a pause symbol while their camera is paused.
private struct CallStageTile: View {
    let engine: any CallEngineActions
    let source: CallVideoSource
    let session: CallSession
    let partnerName: String

    var body: some View {
        CallVideoView(engine: engine, source: source)
            .overlay {
                if source == .partner {
                    CallPartnerVideoCover(session: session, partnerName: partnerName)
                }
            }
    }
}

/// Covers the partner's last frame while their video has stopped, so it never stands still as if
/// they had frozen. A paused camera says so, and a stall shows a spinner until frames come again.
struct CallPartnerVideoCover: View {
    let session: CallSession
    let partnerName: String

    var body: some View {
        ZStack {
            if session.partnerCamera == .paused {
                cover {
                    VStack(spacing: PaeoniaSpacing.space8) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(.callsPartnerCameraPaused(partnerName))
                            .font(PaeoniaTypography.caption)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(PaeoniaSpacing.space8)
                }
            } else if session.isPartnerVideoStalled, session.partnerCamera == .on {
                cover { ProgressView().tint(.white) }
            }
        }
        .animation(PaeoniaMotion.standardCurve(duration: 0.3), value: session.partnerCamera)
        .animation(PaeoniaMotion.standardCurve(duration: 0.3), value: session.isPartnerVideoStalled)
    }

    /// What VoiceOver says about the partner's video while it has stopped.
    static func accessibilityValue(of session: CallSession, partnerName: String) -> Text {
        if session.partnerCamera == .paused { return Text(.callsPartnerCameraPaused(partnerName)) }
        if session.isPartnerVideoStalled { return Text(.callsPartnerVideoStalled(partnerName)) }
        return Text(verbatim: "")
    }

    /// The material blurs the video under it, which is a UIKit view that a SwiftUI blur can't reach.
    private func cover(@ViewBuilder _ content: () -> some View) -> some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay { content() }
            .transition(.opacity)
    }
}
