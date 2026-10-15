import PencilKit
import SwiftUI

/// A finished figure: the three parts stacked with no gap, head on top, with a
/// 2 pt hairline at each fold so the parts stay readable. Each part is drawn the
/// way Draw & Guess draws a finished drawing, so strokes look the same.
///
/// A part that is not on the phone yet shows a small spinner in its own panel. The
/// caller adds the VoiceOver label, because it knows the figure's number and who
/// drew it.
struct ExquisiteCorpseFigureView: View {
    /// The parts at the canonical side. A part that is missing is still loading.
    let parts: [ExquisiteCorpsePartKind: PKDrawing]
    /// The side of one part. The figure is three times as tall.
    let side: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.order, id: \.rawValue) { kind in
                part(parts[kind])
            }
        }
        .frame(width: side, height: side * CGFloat(Self.order.count))
        .background(.paeoniaBackgroundPrimary)
        .overlay(alignment: .top) {
            folds
        }
    }

    private static let order: [ExquisiteCorpsePartKind] = [.head, .body, .legs]

    private func part(_ drawing: PKDrawing?) -> some View {
        ZStack {
            if let drawing {
                GameStaticDrawing(drawing: drawing, side: side)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            } else {
                ExquisiteCorpsePartSpinner()
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        // Only opacity changes, so this also suits Reduce Motion.
        .animation(PaeoniaMotion.meaningfulMoment, value: drawing == nil)
    }

    /// A hairline centered on each fold.
    private var folds: some View {
        ZStack(alignment: .top) {
            ForEach(1..<Self.order.count, id: \.self) { index in
                Rectangle()
                    .fill(.paeoniaTextTertiary.opacity(0.3))
                    .frame(height: Self.hairline)
                    .offset(y: side * CGFloat(index) - Self.hairline / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let hairline: CGFloat = 2
}

/// A small spinner that waits a moment before it shows, so a part that arrives
/// quickly never flashes it.
private struct ExquisiteCorpsePartSpinner: View {
    @State private var isShown = false

    var body: some View {
        ProgressView()
            .tint(.paeoniaAccentPrimary)
            .opacity(isShown ? 1 : 0)
            .accessibilityLabel(Text(.gamesDrawingLoading))
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(PaeoniaMotion.stateChange) { isShown = true }
            }
    }
}

#if DEBUG
#Preview {
    HStack(alignment: .top, spacing: PaeoniaSpacing.space24) {
        ExquisiteCorpseFigureView(
            parts: [
                .head: ExquisiteCorpsePreviewDrawings.head,
                .body: ExquisiteCorpsePreviewDrawings.body,
                .legs: ExquisiteCorpsePreviewDrawings.legs,
            ],
            side: 100
        )
        // The legs are still loading.
        ExquisiteCorpseFigureView(
            parts: [
                .head: ExquisiteCorpsePreviewDrawings.head,
                .body: ExquisiteCorpsePreviewDrawings.body,
            ],
            side: 100
        )
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
