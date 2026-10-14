import SwiftUI

/// One closed box. With a photo it shows the box's piece of the picture under a
/// 30% tint of the owner's color, with the owner's mark small in the top leading
/// corner. Without a photo it is filled with the owner's color and the mark in
/// the middle.
///
/// A box that was just closed scales up from 0.85, fades in and gets one
/// shimmer of the owner's color. When the game ends, the tint and the mark lift
/// off, the gap around the piece closes, and the 16 pieces make one picture.
struct DotsAndBoxesBoxView: View {
    let box: Int
    let style: BoardPieceStyle
    let geometry: DotsAndBoxesBoardGeometry
    let photo: UIImage?
    /// 0 while the game is on, 1 once the outcome lifted the tints off the photo.
    let reveal: Double
    let isDimmed: Bool
    /// The box pulses each time this goes up. Going down, as it does when a new game
    /// starts, does nothing.
    let pulseTrigger: Int
    let pulseDelay: TimeInterval

    /// Seconds to wait before appearing, or nil for a box that was already closed.
    private let entranceDelay: TimeInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear: Double
    @State private var shimmer: Double
    @State private var pulseCount = 0

    private static let tintOpacity = 0.3
    private static let fillOpacity = 0.35
    private static let dimmedOpacity = 0.4

    init(
        box: Int,
        style: BoardPieceStyle,
        geometry: DotsAndBoxesBoardGeometry,
        photo: UIImage?,
        reveal: Double,
        isDimmed: Bool,
        pulseTrigger: Int,
        pulseDelay: TimeInterval,
        entranceDelay: TimeInterval?
    ) {
        self.box = box
        self.style = style
        self.geometry = geometry
        self.photo = photo
        self.reveal = reveal
        self.isDimmed = isDimmed
        self.pulseTrigger = pulseTrigger
        self.pulseDelay = pulseDelay
        self.entranceDelay = entranceDelay
        _appear = State(initialValue: entranceDelay == nil ? 1 : 0)
        _shimmer = State(initialValue: entranceDelay == nil ? 1 : 0)
    }

    /// How far the tint, the mark and the gaps have lifted. A plain box has none of that.
    private var lift: Double {
        photo == nil ? 0 : reveal
    }

    private var entranceScale: CGFloat {
        reduceMotion ? 1 : 0.85 + 0.15 * CGFloat(appear)
    }

    var body: some View {
        let rect = geometry.boxRect(box)
        let inset = geometry.pieceGap * (1 - lift)
        let size = CGSize(width: rect.width - inset * 2, height: rect.height - inset * 2)
        piece(size: size, inset: inset)
            .clipShape(RoundedRectangle(cornerRadius: geometry.pieceCornerRadius * (1 - lift), style: .continuous))
            .keyframeAnimator(initialValue: 1.0, trigger: pulseCount) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(1.0, duration: pulseDelay + 0.001)
                    CubicKeyframe(1.12, duration: 0.16)
                    CubicKeyframe(1.0, duration: 0.3)
                }
            }
            .scaleEffect(entranceScale)
            .opacity(appear * (isDimmed ? Self.dimmedOpacity : 1))
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .onAppear { playEntrance() }
            .onChange(of: pulseTrigger) { old, new in
                if new > old { pulseCount += 1 }
            }
    }

    // MARK: Piece

    private func piece(size: CGSize, inset: CGFloat) -> some View {
        ZStack {
            if let photo {
                photoPiece(photo, size: size, inset: inset)
                style.color.opacity(Self.tintOpacity * (1 - lift))
                cornerMark.opacity(1 - lift)
            } else {
                style.color.opacity(Self.fillOpacity)
                centerMark
            }
            shimmerBand
        }
        .frame(width: size.width, height: size.height)
    }

    /// This box's part of the photo. Every box lays out the whole photo at the
    /// size of the grid and shows only its own square, so the pieces line up.
    private func photoPiece(_ photo: UIImage, size: CGSize, inset: CGFloat) -> some View {
        let origin = geometry.photoPieceRect(forBox: box).origin
        return Image(uiImage: photo)
            .resizable()
            .scaledToFill()
            .frame(width: geometry.photoSide, height: geometry.photoSide)
            .clipped()
            .offset(x: -(origin.x + inset), y: -(origin.y + inset))
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .accessibilityHidden(true)
    }

    private var cornerMark: some View {
        BoardMarkView(style: style, tint: .paeoniaTextPrimary)
            .frame(width: geometry.cell * 0.22, height: geometry.cell * 0.22)
            .shadow(color: .paeoniaBackgroundSecondary.opacity(0.6), radius: 1.5, y: 0.5)
            .padding(geometry.cell * 0.07)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var centerMark: some View {
        BoardMarkView(style: style, tint: .paeoniaTextPrimary)
            .frame(width: geometry.cell * 0.55, height: geometry.cell * 0.55)
    }

    /// A soft band of the owner's color that crosses the box once.
    private var shimmerBand: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(
                colors: [style.color.opacity(0), style.color.opacity(0.75), style.color.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.7)
            .offset(x: -width * 0.7 + shimmer * width * 1.7)
        }
        .allowsHitTesting(false)
    }

    // MARK: Entrance

    private func playEntrance() {
        guard let entranceDelay else { return }
        if reduceMotion {
            shimmer = 1
            withAnimation(DotsAndBoxesMotion.fade) { appear = 1 }
        } else {
            withAnimation(DotsAndBoxesMotion.boxPop.delay(entranceDelay)) { appear = 1 }
            withAnimation(DotsAndBoxesMotion.shimmer.delay(entranceDelay + 0.05)) { shimmer = 1 }
        }
    }
}
