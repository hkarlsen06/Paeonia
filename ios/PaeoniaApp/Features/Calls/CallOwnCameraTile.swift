import SwiftUI

/// The corner of the call screen your own camera sits in.
nonisolated struct CallOwnCameraCorner: Equatable, Sendable {
    var vertical: VerticalEdge
    var horizontal: HorizontalEdge

    /// Top right, under the chevron's row.
    static let initial = CallOwnCameraCorner(vertical: .top, horizontal: .trailing)

    var alignment: Alignment {
        Alignment(
            horizontal: horizontal == .leading ? .leading : .trailing,
            vertical: vertical == .top ? .top : .bottom
        )
    }

    var anchor: UnitPoint {
        UnitPoint(x: horizontal == .leading ? 0 : 1, y: vertical == .top ? 0 : 1)
    }
}

extension CallOwnCameraCorner {
    /// The corner of an area of `size` that `point` is nearest.
    init(nearest point: CGPoint, in size: CGSize) {
        self.init(
            vertical: point.y < size.height / 2 ? .top : .bottom,
            horizontal: point.x < size.width / 2 ? .leading : .trailing
        )
    }
}

/// Your own camera in a corner of the call screen, under the chevron's row or above the controls.
/// As in FaceTime, the person drags it anywhere, and it settles in the corner the throw heads for.
/// While the controls are hidden it moves into the room they leave, unless Reduce Motion is on.
struct CallOwnCameraTile: View {
    let engine: any CallEngineActions
    @Binding var corner: CallOwnCameraCorner
    let showsHUD: Bool
    /// From the bottom of the safe area to the top of the controls.
    let controlsHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset = CGSize.zero
    @State private var area = CGSize.zero

    private static let size = CGSize(width: 104, height: 152)
    private static let space = "callOwnCameraArea"

    var body: some View {
        CallVideoView(engine: engine, source: .local)
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(.rect(cornerRadius: PaeoniaRadius.radius20))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius20).strokeBorder(.white.opacity(0.25))
            }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            // The video view takes no touches, so without a shape the drag reaches the screen behind.
            .contentShape(.rect(cornerRadius: PaeoniaRadius.radius20))
            .offset(dragOffset)
            .gesture(drag)
            .accessibilityElement()
            .accessibilityLabel(Text(.callsYourCamera))
            .padding(.top, showsHUD || reduceMotion
                ? PaeoniaSpacing.compactButtonHeight + PaeoniaSpacing.space16
                : PaeoniaSpacing.space8)
            .padding(.bottom, showsHUD || reduceMotion
                ? controlsHeight + PaeoniaSpacing.space16
                : PaeoniaSpacing.space24)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { area = $0 }
            .coordinateSpace(.named(Self.space))
    }

    /// Takes the drag from the call screen's swipe down, so moving the camera never shrinks the call.
    private var drag: some Gesture {
        DragGesture(coordinateSpace: .named(Self.space))
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.15)) {
                    corner = CallOwnCameraCorner(nearest: value.predictedEndLocation, in: area)
                    dragOffset = .zero
                }
            }
    }
}
