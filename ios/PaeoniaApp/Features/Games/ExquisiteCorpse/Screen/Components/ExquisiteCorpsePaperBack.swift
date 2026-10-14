import SwiftUI

/// The back of a folded sheet of paper, seen from the front. A soft vertical
/// gradient with a 1 pt highlight along the bottom edge, where the fold is, so
/// the sheet reads as folded toward the viewer. The folded paper, the small
/// progress paper and the hub artwork all use it.
struct ExquisiteCorpsePaperBack: View {
    var body: some View {
        LinearGradient(
            colors: [.paeoniaSurfaceSecondary, .paeoniaSurfacePrimary],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.paeoniaTextPrimary.opacity(0.22))
                .frame(height: PaeoniaRadius.strokeDefault)
        }
        .accessibilityHidden(true)
    }
}

/// A straight line across the middle of its frame. Stroke it with a dash and
/// give it a frame as tall as the line is thick.
struct ExquisiteCorpseHorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
