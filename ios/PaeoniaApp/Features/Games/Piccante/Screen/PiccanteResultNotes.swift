import SwiftUI

enum PiccanteNoteColors {
    static let paper = Color.paeoniaSurfacePrimary
    static let ink = Color.paeoniaTextPrimary
}

struct PiccanteResultNotes: View {
    let game: RemotePiccanteGame
    let userID: UUID?
    let partnerName: String

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            if Set(game.chilis.map(\.tile)).count == 1 {
                Label {
                    Text(.piccanteSameOne)
                } icon: {
                    Image(systemName: "heart.fill")
                }
                .font(PaeoniaTypography.title)
                .foregroundStyle(Color.paeoniaInkGold)
            }
            ForEach(partnerChilis.indices, id: \.self) { index in
                let chili = partnerChilis[index]
                if let note = chili.note {
                    notePaper(note, chili: chili)
                }
            }
        }
    }

    private func notePaper(_ note: String, chili: PiccanteChili) -> some View {
        return VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(heading(for: chili))
                .font(PaeoniaTypography.caption.weight(.semibold))
            Text(verbatim: note)
                .font(Font.system(.body, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(.piccanteNoteFrom(partnerName))
                .font(PaeoniaTypography.caption)
        }
        .foregroundStyle(PiccanteNoteColors.ink)
        .multilineTextAlignment(.leading)
        .padding(PaeoniaSpacing.space20)
        .padding(.trailing, PaeoniaSpacing.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paeoniaCardSurface(
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12),
            fill: PiccanteNoteColors.paper
        )
        .overlay(alignment: .topTrailing) {
            PiccantePaperFold()
                .fill(PiccanteNoteColors.ink.opacity(0.12))
                .frame(width: 22, height: 22)
                .padding(1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func heading(for chili: PiccanteChili) -> LocalizedStringResource {
        chili.userID == game.winnerUserID ? .piccanteNoteForYou : .piccanteWouldHaveGot
    }

    private var partnerChilis: [PiccanteChili] {
        guard let userID else { return [] }
        return game.chilis.filter { $0.userID != userID }
    }
}

nonisolated private struct PiccantePaperFold: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
