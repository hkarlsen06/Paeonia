import SwiftUI

/// One Mind Meld word card. Face down it shows the petal mark. Face up it shows
/// the word in capitals. The flip is a turn around the vertical axis, driven by
/// `isFaceUp` and the animation of the change, so the caller sets the timing.
/// With Reduce Motion the card cross-fades instead of turning.
struct MindMeldWordCard: View {
    enum Tone: Equatable {
        /// A quiet border.
        case plain
        /// An accent border, for words that are almost the same.
        case near
        /// A green border and a small petal mark, for a meld.
        case success
    }

    /// Nil is fine while the card is face down.
    let word: String?
    let isFaceUp: Bool
    /// What VoiceOver reads while the card is face down. Face up it reads the word.
    let faceDownLabel: LocalizedStringResource
    var tone: Tone = .plain
    /// Shows a lock on a face-up card, for the word this person has locked in.
    var isLocked = false
    /// A soft glow that breathes around a face-down card while the partner is in the game.
    var breathes = false
    var maxWidth: CGFloat = 160

    private static let aspectRatio: CGFloat = 0.8
    private static let radius = PaeoniaRadius.radius20
    private static let breathingDuration: TimeInterval = 2.4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The card is at least this tall, and grows with the text size.
    @ScaledMetric(relativeTo: .title2) private var minimumHeight: CGFloat = 150
    @State private var isBreathing = false

    var body: some View {
        // The invisible base sets the size: 4:5, taller at large text sizes. The faces
        // are drawn over it, so spare height in the parent never stretches the card.
        Color.clear
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .frame(minHeight: minimumHeight)
            .overlay {
                ZStack {
                    breathingGlow
                    faces
                        .shadow(color: shadowColor.opacity(0.22), radius: 18, y: 8)
                        .shadow(color: .paeoniaBackgroundSecondary.opacity(0.5), radius: 10, y: 6)
                }
            }
            .frame(maxWidth: maxWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .onAppear { isBreathing = true }
    }

    // MARK: Faces

    @ViewBuilder
    private var faces: some View {
        if reduceMotion {
            ZStack {
                back.opacity(isFaceUp ? 0 : 1)
                front.opacity(isFaceUp ? 1 : 0)
            }
            .animation(PaeoniaMotion.stateChange, value: isFaceUp)
        } else {
            MindMeldCardFlip(angle: isFaceUp ? 180 : 0, back: back, front: front)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
    }

    private var back: some View {
        ZStack {
            shape.fill(.paeoniaSurfaceSecondary)
            MindMeldCardPattern()
                .clipShape(shape)
            // A thin inner frame, like the back of a playing card.
            RoundedRectangle(cornerRadius: Self.radius - PaeoniaSpacing.space8, style: .continuous)
                .strokeBorder(Color.paeoniaAccentPrimary.opacity(0.2), lineWidth: PaeoniaRadius.strokeHairline)
                .padding(PaeoniaSpacing.space8)
            Circle()
                .fill(Color.paeoniaAccentPrimary.opacity(0.12))
                .overlay(
                    Circle().strokeBorder(
                        Color.paeoniaAccentPrimary.opacity(0.3),
                        lineWidth: PaeoniaRadius.strokeHairline
                    )
                )
                .frame(width: 56, height: 56)
            MindMeldPetalMark()
                .frame(width: 30, height: 30)
                .foregroundStyle(Color.paeoniaAccentPrimary.opacity(0.6))
        }
        .overlay { border }
    }

    private var front: some View {
        ZStack {
            shape.fill(.paeoniaSurfacePrimary)
            // A little light from the top gives the card some depth.
            shape.fill(LinearGradient(
                colors: [Color.paeoniaTextPrimary.opacity(0.07), .clear],
                startPoint: .top,
                endPoint: .center
            ))
            Text(verbatim: (word ?? "").localizedUppercase)
                .font(PaeoniaTypography.title)
                .tracking(0.6)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.paeoniaTextPrimary)
                .padding(.horizontal, PaeoniaSpacing.space12)
                .padding(.vertical, PaeoniaSpacing.space24)
        }
        .overlay(alignment: .top) {
            if tone == .success {
                MindMeldPetalMark()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.paeoniaSuccess)
                    .padding(.top, PaeoniaSpacing.space12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(PaeoniaTypography.caption.weight(.bold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .padding(PaeoniaSpacing.space8)
                    .background(Color.paeoniaAccentPrimary.opacity(0.16), in: Circle())
                    .padding(PaeoniaSpacing.space8)
                    .accessibilityHidden(true)
            }
        }
        .overlay { border }
    }

    private var border: some View {
        shape
            .strokeBorder(
                borderColor,
                lineWidth: tone == .plain ? PaeoniaRadius.strokeDefault : PaeoniaRadius.strokeEmphasis
            )
            .animation(PaeoniaMotion.stateChange, value: tone)
            .allowsHitTesting(false)
    }

    private var borderColor: Color {
        switch tone {
        case .plain: .paeoniaSurfacePressed
        case .near: .paeoniaAccentPrimary
        case .success: .paeoniaSuccess
        }
    }

    private var shadowColor: Color {
        tone == .success ? .paeoniaSuccess : .paeoniaAccentPrimary
    }

    // MARK: Breathing glow

    /// Fades in and out while the partner is in the game. It stays in the layout,
    /// so the card does not shift when the partner arrives or leaves.
    private var breathingGlow: some View {
        shape
            .stroke(.paeoniaAccentPrimary, lineWidth: 6)
            .blur(radius: 8)
            .animation(reduceMotion ? nil : breathing) {
                $0.opacity(reduceMotion ? 0.35 : isBreathing ? 0.5 : 0.2)
            }
            .opacity(breathes ? 1 : 0)
            .animation(PaeoniaMotion.stateChange, value: breathes)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var breathing: Animation {
        PaeoniaMotion.standardCurve(duration: Self.breathingDuration).repeatForever(autoreverses: true)
    }

    // MARK: Accessibility

    private var accessibilityText: Text {
        isFaceUp ? Text(verbatim: (word ?? "").localizedUppercase) : Text(faceDownLabel)
    }
}

/// The two faces on a turning card. Up to 90 degrees the back shows, after that
/// the front. The front is turned a half circle first, so its text is never mirrored.
private struct MindMeldCardFlip<Back: View, Front: View>: View, Animatable {
    /// 0 for face down, 180 for face up.
    var angle: Double
    let back: Back
    let front: Front

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        ZStack {
            back.opacity(angle < 90 ? 1 : 0)
            front
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(angle < 90 ? 0 : 1)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

/// A faint lattice of tiny petals on the back of a card.
private struct MindMeldCardPattern: View {
    private static let spacing: CGFloat = 22
    private static let markSize: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let petal = MindMeldPetalShape()
            let tint = GraphicsContext.Shading.color(Color.paeoniaAccentPrimary.opacity(0.07))
            var row = 0
            var y = Self.spacing / 2
            while y < size.height {
                var x = Self.spacing / 2 + (row.isMultiple(of: 2) ? 0 : Self.spacing / 2)
                while x < size.width {
                    let rect = CGRect(
                        x: x - Self.markSize / 2,
                        y: y - Self.markSize / 2,
                        width: Self.markSize,
                        height: Self.markSize
                    )
                    context.fill(petal.path(in: rect), with: tint)
                    x += Self.spacing
                }
                y += Self.spacing
                row += 1
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("States") {
    @Previewable @State var isFaceUp = false
    let hidden = LocalizedStringResource.mindMeldRevealCardFacedownA11Y("Robin")
    VStack(spacing: PaeoniaSpacing.space24) {
        HStack(spacing: PaeoniaSpacing.space24) {
            MindMeldWordCard(word: "Ocean", isFaceUp: isFaceUp, faceDownLabel: hidden, breathes: true)
            MindMeldWordCard(word: "Ice cream", isFaceUp: true, faceDownLabel: hidden, isLocked: true)
        }
        HStack(spacing: PaeoniaSpacing.space24) {
            MindMeldWordCard(word: "Oceans", isFaceUp: true, faceDownLabel: hidden, tone: .near)
            MindMeldWordCard(word: "Fish", isFaceUp: true, faceDownLabel: hidden, tone: .success)
        }
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.14)) { isFaceUp.toggle() }
        } label: {
            Text(verbatim: "Flip")
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
